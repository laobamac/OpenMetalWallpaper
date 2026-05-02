//
//  TexModels.swift
//  Renderer
//
//  Created by laobamac on 2026/3/13.
//

import Foundation

enum TexFormat: Int32, Sendable {
    case RGBA8888 = 0
    case DXT5 = 4
    case DXT3 = 6
    case DXT1 = 7
    case RG88 = 8
    case R8 = 9
}

struct TexFlags: Sendable, Equatable {
    let rawValue: Int32
    
    static let none = TexFlags(rawValue: 0)
    static let noInterpolation = TexFlags(rawValue: 1)
    static let clampUVs = TexFlags(rawValue: 2)
    static let isGif = TexFlags(rawValue: 4)
    static let isVideoTexture = TexFlags(rawValue: 32)
    
    func contains(_ flag: TexFlags) -> Bool {
        if flag.rawValue == 0 {
            return true
        }
        return (self.rawValue & flag.rawValue) == flag.rawValue
    }
}

enum FreeImageFormat: Int32, Sendable {
    case unknown = -1
    case bmp = 0
    case ico = 1
    case jpeg = 2
    case jng = 3
    case koala = 4
    case lbm = 5
    case mng = 6
    case pbm = 7
    case pbmraw = 8
    case pcd = 9
    case pcx = 10
    case pgm = 11
    case pgmraw = 12
    case png = 13
    case ppm = 14
    case ppmraw = 15
    case ras = 16
    case targa = 17
    case tiff = 18
    case wbmp = 19
    case psd = 20
    case cut = 21
    case xbm = 22
    case xpm = 23
    case dds = 24
    case gif = 25
    case hdr = 26
    case faxg3 = 27
    case sgi = 28
    case exr = 29
    case j2k = 30
    case jp2 = 31
    case pfm = 32
    case pict = 33
    case raw = 34
    case mp4 = 35
}

enum TexImageContainerVersion: Int32, Sendable {
    case version1 = 1
    case version2 = 2
    case version3 = 3
    case version4 = 4
}

enum MipmapFormat: Int32, Sendable {
    case invalid = 0
    case rgba8888 = 1
    case r8 = 2
    case rg88 = 3
    case compressedDXT5 = 4
    case compressedDXT3 = 5
    case compressedDXT1 = 6
    case videoMp4 = 7
    case imagePNG = 1013
    case imageGIF = 1025
    case imageJPEG = 1002
}

struct TexHeader: Sendable {
    var format: TexFormat
    var flags: TexFlags
    var textureWidth: Int32
    var textureHeight: Int32
    var imageWidth: Int32
    var imageHeight: Int32
    var unkInt0: UInt32
}

struct TexMipmap: Sendable {
    var width: Int32
    var height: Int32
    var isLz4Compressed: Bool
    var decompressedBytesCount: Int32
    var bytesData: Data
    var format: MipmapFormat
}

struct TexImage: Sendable {
    var mipmaps: [TexMipmap]
}

struct TexImageContainer: Sendable {
    var magic: String
    var imageFormat: FreeImageFormat
    var version: TexImageContainerVersion
    var images: [TexImage]
}

struct TexFrameInfo: Sendable {
    var imageId: Int32
    var frametime: Float
    var x: Float
    var y: Float
    var width: Float
    var widthY: Float
    var heightX: Float
    var height: Float
}

struct TexFrameInfoContainer: Sendable {
    var magic: String
    var gifWidth: Int32
    var gifHeight: Int32
    var frames: [TexFrameInfo]
}

struct TexFile: Sendable {
    var magic1: String
    var magic2: String
    var header: TexHeader
    var imageContainer: TexImageContainer
    var frameInfoContainer: TexFrameInfoContainer?
}
