//
//  TexParser.swift
//  Renderer
//
//  Created by laobamac on 2026/3/13.
//

import Foundation
import Compression

struct BinaryReader {
    private var data: Data
    private var offset: Int = 0

    init(data: Data) {
        self.data = data
    }

    mutating func readInt32() -> Int32 {
        guard offset + 4 <= data.count else { return 0 }
        let value = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: Int32.self) }
        offset += 4
        return value
    }

    mutating func readUInt32() -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        let value = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
        offset += 4
        return value
    }

    mutating func readSingle() -> Float {
        guard offset + 4 <= data.count else { return 0 }
        let value = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: Float.self) }
        offset += 4
        return value
    }

    mutating func readBytes(count: Int) -> Data {
        guard offset + count <= data.count else {
            let safeCount = max(0, data.count - offset)
            let subData = data.subdata(in: offset..<(offset + safeCount))
            offset += safeCount
            return subData
        }
        let subData = data.subdata(in: offset..<(offset + count))
        offset += count
        return subData
    }

    mutating func readNString(maxLength: Int = -1) -> String {
        var chars: [UInt8] = []
        while offset < data.count {
            let charByte = data[offset]
            offset += 1
            if charByte == 0 { break }
            chars.append(charByte)
            if maxLength > 0 && chars.count >= maxLength { break }
        }
        return String(bytes: chars, encoding: .utf8) ?? ""
    }
}

enum TexParser {
    static func parse(data: Data) async throws -> TexFile {
        Logger.debug("TexParser 开始解析数据，总大小: \(data.count) 字节")
        var reader = BinaryReader(data: data)
        
        let magic1 = reader.readNString(maxLength: 16)
        if magic1 != "TEXV0005" {
            Logger.error("TEXV 魔法字不匹配，读取到: \(magic1)")
            throw NSError(domain: "TexParser", code: 1, userInfo: nil)
        }
        
        let magic2 = reader.readNString(maxLength: 16)
        if magic2 != "TEXI0001" {
            Logger.error("TEXI 魔法字不匹配，读取到: \(magic2)")
            throw NSError(domain: "TexParser", code: 2, userInfo: nil)
        }

        Logger.debug("魔法字校验通过")
        let header = readHeader(reader: &reader)
        Logger.debug("头部解析完成: 格式=\(header.format), 宽度=\(header.textureWidth), 高度=\(header.textureHeight), 标志=\(header.flags.rawValue)")
        
        let imageContainer = try await readImageContainer(reader: &reader, texFormat: header.format)
        Logger.debug("图片容器解析完成: 包含 \(imageContainer.images.count) 张图像, 容器格式=\(imageContainer.imageFormat)")

        var frameInfo: TexFrameInfoContainer? = nil
        if header.flags.contains(.isGif) {
            Logger.debug("检测到 GIF 标志，开始解析 FrameInfo")
            frameInfo = readFrameInfo(reader: &reader)
            Logger.debug("FrameInfo 解析完成，帧数: \(frameInfo?.frames.count ?? 0)")
        }

        Logger.debug("TEX 文件解析全部完成")
        return TexFile(magic1: magic1, magic2: magic2, header: header, imageContainer: imageContainer, frameInfoContainer: frameInfo)
    }

    static func parse(fileURL: URL) async throws -> TexFile {
        Logger.debug("读取 TEX 文件: \(fileURL.path)")
        let data = try Data(contentsOf: fileURL)
        return try await parse(data: data)
    }

    private static func readHeader(reader: inout BinaryReader) -> TexHeader {
        let fmtVal = reader.readInt32()
        let format = TexFormat(rawValue: fmtVal) ?? .RGBA8888
        let flags = TexFlags(rawValue: reader.readInt32())
        let tw = reader.readInt32()
        let th = reader.readInt32()
        let iw = reader.readInt32()
        let ih = reader.readInt32()
        let unk = reader.readUInt32()
        return TexHeader(format: format, flags: flags, textureWidth: tw, textureHeight: th, imageWidth: iw, imageHeight: ih, unkInt0: unk)
    }

    private static func readImageContainer(reader: inout BinaryReader, texFormat: TexFormat) async throws -> TexImageContainer {
        let magic = reader.readNString(maxLength: 16)
        let imageCount = reader.readInt32()
        Logger.debug("ImageContainer 魔法字: \(magic), 图片数量: \(imageCount)")
        
        var imageFmt = FreeImageFormat.unknown
        var version = TexImageContainerVersion.version1

        if magic == "TEXB0003" {
            imageFmt = FreeImageFormat(rawValue: reader.readInt32()) ?? .unknown
            version = .version3
        } else if magic == "TEXB0004" {
            imageFmt = FreeImageFormat(rawValue: reader.readInt32()) ?? .unknown
            let isVideoMp4 = reader.readInt32() == 1
            if imageFmt == .unknown && isVideoMp4 {
                imageFmt = .mp4
            }
            version = .version4
        } else {
            if magic.hasPrefix("TEXB") {
                let verString = magic.dropFirst(4)
                if let verNum = Int32(verString), let v = TexImageContainerVersion(rawValue: verNum) {
                    version = v
                }
            }
        }

        if version == .version4 && imageFmt != .mp4 {
            version = .version3
        }
        
        Logger.debug("确定容器版本: \(version), 图片格式: \(imageFmt)")
        var images: [TexImage] = []
        for i in 0..<imageCount {
            Logger.debug("正在读取第 \(i) 张图片数据...")
            images.append(try await readImage(reader: &reader, version: version, containerFmt: imageFmt, texFmt: texFormat))
        }
        
        return TexImageContainer(magic: magic, imageFormat: imageFmt, version: version, images: images)
    }

    private static func readImage(reader: inout BinaryReader, version: TexImageContainerVersion, containerFmt: FreeImageFormat, texFmt: TexFormat) async throws -> TexImage {
        let mipmapCount = reader.readInt32()
        Logger.debug("  -> 包含 \(mipmapCount) 个 Mipmap 层级")
        var mipmaps: [TexMipmap] = []
        let mipmapFmt = getMipmapFormat(containerFmt: containerFmt, texFmt: texFmt)

        for j in 0..<mipmapCount {
            var mm = readMipmap(reader: &reader, version: version)
            mm.format = mipmapFmt
            if mm.isLz4Compressed {
                Logger.debug("    -> 发现 LZ4 压缩，尝试解压 Mipmap \(j) (未解压大小: \(mm.decompressedBytesCount))")
                let bytesData = mm.bytesData
                let decompressedBytesCount = mm.decompressedBytesCount
                let decompressed = await Task.detached(priority: .userInitiated) {
                    return decompressLZ4(data: bytesData, uncompressedSize: Int(decompressedBytesCount))
                }.value
                
                if let decompressedData = decompressed {
                    mm.bytesData = decompressedData
                    Logger.debug("    -> LZ4 解压成功")
                } else {
                    mm.bytesData = Data(count: Int(mm.decompressedBytesCount))
                    Logger.error("    -> LZ4 解压失败，填充空数据")
                }
                mm.isLz4Compressed = false
            }
            mipmaps.append(mm)
        }
        
        return TexImage(mipmaps: mipmaps)
    }

    private static func readMipmap(reader: inout BinaryReader, version: TexImageContainerVersion) -> TexMipmap {
        let width = reader.readInt32()
        let height = reader.readInt32()
        var isLz4 = false
        var decompLen: Int32 = 0

        if version == .version2 || version == .version3 {
            isLz4 = reader.readInt32() == 1
            decompLen = reader.readInt32()
        } else if version == .version4 {
            _ = reader.readInt32()
            _ = reader.readInt32()
            _ = reader.readNString()
            _ = reader.readInt32()
            isLz4 = reader.readInt32() == 1
            decompLen = reader.readInt32()
        }

        let byteCount = reader.readInt32()
        let data = reader.readBytes(count: Int(byteCount))

        if version == .version1 {
            decompLen = byteCount
        }

        Logger.debug("    -> 读入 Mipmap: \(width)x\(height), 数据大小: \(byteCount), LZ4: \(isLz4)")
        return TexMipmap(width: width, height: height, isLz4Compressed: isLz4, decompressedBytesCount: decompLen, bytesData: data, format: .invalid)
    }

    private static func readFrameInfo(reader: inout BinaryReader) -> TexFrameInfoContainer {
        let magic = reader.readNString(maxLength: 16)
        let count = reader.readInt32()
        Logger.debug("FrameInfo 魔法字: \(magic), 包含 \(count) 帧")
        
        var gifW: Int32 = 0
        var gifH: Int32 = 0

        if magic == "TEXS0003" {
            gifW = reader.readInt32()
            gifH = reader.readInt32()
        }

        var frames: [TexFrameInfo] = []
        let isFloat = (magic == "TEXS0002" || magic == "TEXS0003")

        for _ in 0..<count {
            let imgId = reader.readInt32()
            let ft = reader.readSingle()
            var x: Float = 0
            var y: Float = 0
            var w: Float = 0
            var wy: Float = 0
            var hx: Float = 0
            var h: Float = 0

            if isFloat {
                x = reader.readSingle()
                y = reader.readSingle()
                w = reader.readSingle()
                wy = reader.readSingle()
                hx = reader.readSingle()
                h = reader.readSingle()
            } else {
                x = Float(reader.readInt32())
                y = Float(reader.readInt32())
                w = Float(reader.readInt32())
                wy = Float(reader.readInt32())
                hx = Float(reader.readInt32())
                h = Float(reader.readInt32())
            }
            
            frames.append(TexFrameInfo(imageId: imgId, frametime: ft, x: x, y: y, width: w, widthY: wy, heightX: hx, height: h))
        }

        if gifW == 0 && !frames.isEmpty {
            gifW = Int32(frames[0].width)
            gifH = Int32(frames[0].height)
        }

        return TexFrameInfoContainer(magic: magic, gifWidth: gifW, gifHeight: gifH, frames: frames)
    }

    private static func getMipmapFormat(containerFmt: FreeImageFormat, texFmt: TexFormat) -> MipmapFormat {
        if containerFmt != .unknown {
            if containerFmt == .mp4 { return .videoMp4 }
            if containerFmt == .png { return .imagePNG }
            if containerFmt == .jpeg { return .imageJPEG }
            if containerFmt == .gif { return .imageGIF }
            return .imagePNG
        }

        switch texFmt {
        case .RGBA8888: return .rgba8888
        case .DXT5: return .compressedDXT5
        case .DXT3: return .compressedDXT3
        case .DXT1: return .compressedDXT1
        case .RG88: return .rg88
        case .R8: return .r8
        }
    }

    nonisolated private static func decompressLZ4(data: Data, uncompressedSize: Int) -> Data? {
        guard data.count > 0, uncompressedSize > 0 else { return nil }
        
        let capacity = uncompressedSize + 1048576
        var decompressedData = Data(count: capacity)
        let offsets = [0, 4, 8, 12, 16]
        
        for offset in offsets {
            guard data.count > offset else { continue }
            let payload = data.subdata(in: offset..<data.count)
            
            for algo in [COMPRESSION_LZ4_RAW, COMPRESSION_LZ4] {
                var decodedBytes = 0
                decompressedData.withUnsafeMutableBytes { dstPointer in
                    payload.withUnsafeBytes { srcPointer in
                        guard let dstBase = dstPointer.baseAddress, let srcBase = srcPointer.baseAddress else { return }
                        decodedBytes = compression_decode_buffer(
                            dstBase.bindMemory(to: UInt8.self, capacity: capacity),
                            capacity,
                            srcBase.bindMemory(to: UInt8.self, capacity: payload.count),
                            payload.count,
                            nil,
                            algo
                        )
                    }
                }
                
                if decodedBytes > 0 {
                    return decompressedData.subdata(in: 0..<decodedBytes)
                }
            }
        }
        
        return nil
    }
}
