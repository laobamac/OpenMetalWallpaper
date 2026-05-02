import MetalKit
import ImageIO
import CoreGraphics

actor TextureManager {
    private var cache: [URL: (MTLTexture, Bool)] = [:]
    private var frameInfoCache: [URL: [TexFrameInfo]] = [:]
    private var videoUpdaters: [URL: VideoTextureUpdater] = [:]
    private var device: MTLDevice?
    private var loader: MTKTextureLoader?
    private var commandQueue: MTLCommandQueue?

    init() {}

    func setup(device: MTLDevice) async {
        self.device = device
        if self.loader == nil {
            self.loader = MTKTextureLoader(device: device)
        }
        if self.commandQueue == nil {
            self.commandQueue = device.makeCommandQueue()
        }
    }

    func frameInfo(for url: URL) -> [TexFrameInfo]? {
        return frameInfoCache[url]
    }

    func loadTexture(
        url: URL,
        options: [MTKTextureLoader.Option: Any]? = nil,
        force2D: Bool = false
    ) async throws -> (MTLTexture, Bool) {
        if let cached = cache[url] { return cached }
        guard let device = self.device, let loader = self.loader else {
            throw NSError(domain: "TextureManager", code: 0, userInfo: nil)
        }

        let texFile = try await TexParser.parse(fileURL: url)
        
        if let frames = texFile.frameInfoContainer?.frames {
            frameInfoCache[url] = frames
        }
        
        let firstMipmap = texFile.imageContainer.images.first?.mipmaps.first
        let isEmbedded = (firstMipmap?.format == .imagePNG || firstMipmap?.format == .imageJPEG || firstMipmap?.format == .imageGIF)
        let isVideo = await texFile.header.flags.contains(.isVideoTexture) || firstMipmap?.format == .videoMp4

        var texWidth = Int(texFile.header.textureWidth)
        var texHeight = Int(texFile.header.textureHeight)

        if let mip = firstMipmap {
            texWidth = Int(mip.width)
            texHeight = Int(mip.height)
        }

        if isEmbedded, let data = firstMipmap?.bytesData {
            if let source = CGImageSourceCreateWithData(data as CFData, nil),
               let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                texWidth = cgImage.width
                texHeight = cgImage.height
            }
        }

        if texWidth <= 0 { texWidth = 1 }
        if texHeight <= 0 { texHeight = 1 }

        let isGif = await texFile.header.flags.contains(.isGif)

        if isEmbedded && !isVideo, let data = firstMipmap?.bytesData {
            let tempTexture = try await loader.newTexture(data: data, options: options)
            
            if force2D {
                cache[url] = (tempTexture, false)
                return (tempTexture, false)
            }

            let desc = MTLTextureDescriptor()
            desc.pixelFormat = tempTexture.pixelFormat
            desc.width = tempTexture.width
            desc.height = tempTexture.height
            desc.textureType = .type2DArray
            desc.arrayLength = 1
            desc.usage = [.shaderRead]

            guard let arrayTexture = device.makeTexture(descriptor: desc),
                  let cmd = commandQueue?.makeCommandBuffer(),
                  let blit = cmd.makeBlitCommandEncoder() else {
                return (tempTexture, false)
            }

            blit.copy(from: tempTexture, sourceSlice: 0, sourceLevel: 0, to: arrayTexture, destinationSlice: 0, destinationLevel: 0, sliceCount: 1, levelCount: 1)
            blit.endEncoding()
            cmd.commit()
            await cmd.completed()
            
            cache[url] = (arrayTexture, false)
            return (arrayTexture, false)
        }

        var useSRGB = true
        if let options = options, let srgbVal = options[.SRGB] as? Bool {
            useSRGB = srgbVal
        }

        var pixelFormat: MTLPixelFormat = useSRGB ? .rgba8Unorm_srgb : .rgba8Unorm
        var bytesPerBlock = 4
        var isCompressed = false
        var needsCPUExpansion = false

        if isVideo {
            pixelFormat = useSRGB ? .bgra8Unorm_srgb : .bgra8Unorm
            bytesPerBlock = 4
            isCompressed = false
            needsCPUExpansion = false
        } else {
            switch texFile.header.format {
            case .DXT1:
                pixelFormat = useSRGB ? .bc1_rgba_srgb : .bc1_rgba
                bytesPerBlock = 8
                isCompressed = true
            case .DXT3:
                pixelFormat = useSRGB ? .bc2_rgba_srgb : .bc2_rgba
                bytesPerBlock = 16
                isCompressed = true
            case .DXT5:
                pixelFormat = useSRGB ? .bc3_rgba_srgb : .bc3_rgba
                bytesPerBlock = 16
                isCompressed = true
            case .RG88, .R8:
                pixelFormat = useSRGB ? .rgba8Unorm_srgb : .rgba8Unorm
                bytesPerBlock = 4
                needsCPUExpansion = true
            case .RGBA8888:
                pixelFormat = useSRGB ? .rgba8Unorm_srgb : .rgba8Unorm
                bytesPerBlock = 4
            }
        }

        let arrayLength = (isGif && !isVideo) ? max(1, texFile.imageContainer.images.count) : 1

        let desc = MTLTextureDescriptor()
        desc.pixelFormat = pixelFormat
        desc.width = texWidth
        desc.height = texHeight
        desc.textureType = force2D ? .type2D : .type2DArray
        desc.arrayLength = force2D ? 1 : arrayLength
        desc.usage = [.shaderRead]

        guard let texture = device.makeTexture(descriptor: desc) else {
            throw NSError(domain: "TextureManager", code: 1, userInfo: nil)
        }

        if isVideo {
            if let mipmap = firstMipmap {
                let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".mp4")
                try? mipmap.bytesData.write(to: tempURL)
                if let cmdQueue = self.commandQueue {
                    let updater = await VideoTextureUpdater(url: tempURL, texture: texture, device: device, commandQueue: cmdQueue)
                    videoUpdaters[url] = updater
                }
            }
            cache[url] = (texture, true)
            return (texture, true)
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<arrayLength {
                if i < texFile.imageContainer.images.count {
                    group.addTask {
                        let image = texFile.imageContainer.images[i]
                        if let mipmap = image.mipmaps.first {
                            var bytesPerRow = 0
                            var bytesPerImage = 0
                            var finalData = mipmap.bytesData

                            if needsCPUExpansion {
                                let totalPixels = texWidth * texHeight
                                var expandedData = Data(count: totalPixels * 4)
                                
                                expandedData.withUnsafeMutableBytes { dstPtr in
                                    finalData.withUnsafeBytes { srcPtr in
                                        guard let dst = dstPtr.bindMemory(to: UInt8.self).baseAddress,
                                              let src = srcPtr.bindMemory(to: UInt8.self).baseAddress else { return }
                                        
                                        if texFile.header.format == .RG88 {
                                            for p in 0..<totalPixels {
                                                let srcIndex = p * 2
                                                let dstIndex = p * 4
                                                let r = src[srcIndex]
                                                let g = src[srcIndex + 1]
                                                dst[dstIndex] = g
                                                dst[dstIndex + 1] = g
                                                dst[dstIndex + 2] = g
                                                dst[dstIndex + 3] = r
                                            }
                                        } else if texFile.header.format == .R8 {
                                            for p in 0..<totalPixels {
                                                let srcIndex = p
                                                let dstIndex = p * 4
                                                let r = src[srcIndex]
                                                dst[dstIndex] = r
                                                dst[dstIndex + 1] = r
                                                dst[dstIndex + 2] = r
                                                dst[dstIndex + 3] = r
                                            }
                                        }
                                    }
                                }
                                finalData = expandedData
                                bytesPerRow = texWidth * 4
                                bytesPerImage = bytesPerRow * texHeight
                            } else if isCompressed {
                                let blocksPerRow = (texWidth + 3) / 4
                                let blocksPerCol = (texHeight + 3) / 4
                                bytesPerRow = blocksPerRow * bytesPerBlock
                                bytesPerImage = bytesPerRow * blocksPerCol
                            } else {
                                bytesPerRow = texWidth * bytesPerBlock
                                bytesPerImage = bytesPerRow * texHeight
                            }
                            
                            if finalData.count < bytesPerImage {
                                finalData.append(Data(count: bytesPerImage - finalData.count))
                            }
                            
                            finalData.withUnsafeBytes { ptr in
                                if let baseAddress = ptr.baseAddress {
                                    let region = MTLRegionMake2D(0, 0, texWidth, texHeight)
                                    texture.replace(
                                        region: region,
                                        mipmapLevel: 0,
                                        slice: force2D ? 0 : i,
                                        withBytes: baseAddress,
                                        bytesPerRow: bytesPerRow,
                                        bytesPerImage: bytesPerImage
                                    )
                                }
                            }
                        }
                    }
                }
            }
            try await group.waitForAll()
        }

        cache[url] = (texture, false)
        return (texture, false)
    }

    func setVolume(_ volume: Float, isMuted: Bool) {
        for updater in videoUpdaters.values {
            updater.isMuted = isMuted
            updater.volume = isMuted ? 0.0 : volume
        }
    }

    func setPlaybackRate(_ rate: Float) {
        for updater in videoUpdaters.values {
            updater.rate = rate
        }
    }

    func clear() async {
        for updater in videoUpdaters.values {
            await updater.stop()
        }
        videoUpdaters.removeAll()
        cache.removeAll()
        frameInfoCache.removeAll()
    }
}
