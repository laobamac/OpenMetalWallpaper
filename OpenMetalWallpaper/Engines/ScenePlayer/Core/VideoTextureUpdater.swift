//
//  VideoTextureUpdater.swift
//  Renderer
//
//  Created by laobamac on 2026/3/14.
//

import AVFoundation
import CoreVideo
import Foundation
import MetalKit

class VideoTextureUpdater: @unchecked Sendable {
    private var player: AVPlayer?
    private var videoOutput: AVPlayerItemVideoOutput?
    private var texture: MTLTexture
    private var videoURL: URL?
    private var displayLink: CVDisplayLink?
    private var textureCache: CVMetalTextureCache?
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    var volume: Float = 0.0 {
        didSet { player?.volume = isMuted ? 0.0 : volume }
    }
    var rate: Float = 1.0 {
        didSet { player?.rate = rate }
    }
    var isMuted: Bool = true {
        didSet { player?.isMuted = isMuted }
    }

    init(url: URL, texture: MTLTexture, device: MTLDevice, commandQueue: MTLCommandQueue) {
        self.texture = texture
        self.videoURL = url
        self.device = device
        self.commandQueue = commandQueue

        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)

        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        self.videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: attributes)

        let playerItem = AVPlayerItem(url: url)
        if let output = self.videoOutput {
            playerItem.add(output)
        }

        self.player = AVPlayer(playerItem: playerItem)
        self.player?.actionAtItemEnd = .none
        self.player?.isMuted = self.isMuted
        self.player?.volume = self.volume

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(loopVideo),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )

        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        if let dl = displayLink {
            let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, userInfo -> CVReturn in
                let updater = Unmanaged<VideoTextureUpdater>.fromOpaque(userInfo!).takeUnretainedValue()
                updater.updateTexture()
                return kCVReturnSuccess
            }
            CVDisplayLinkSetOutputCallback(dl, callback, Unmanaged.passUnretained(self).toOpaque())
            CVDisplayLinkStart(dl)
        }

        self.player?.play()
    }

    @objc private func loopVideo(notification: Notification) {
        guard let item = notification.object as? AVPlayerItem,
              item == player?.currentItem else { return }
        item.seek(to: .zero, completionHandler: nil)
    }

    func updateTexture() {
        guard let output = videoOutput, let cache = textureCache else { return }
        let time = output.itemTime(forHostTime: CACurrentMediaTime())
        if output.hasNewPixelBuffer(forItemTime: time) {
            if let pixelBuffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) {
                let width = CVPixelBufferGetWidth(pixelBuffer)
                let height = CVPixelBufferGetHeight(pixelBuffer)
                var cvTextureOut: CVMetalTexture?
                
                let status = CVMetalTextureCacheCreateTextureFromImage(
                    kCFAllocatorDefault,
                    cache,
                    pixelBuffer,
                    nil,
                    .bgra8Unorm,
                    width,
                    height,
                    0,
                    &cvTextureOut
                )
                
                if status == kCVReturnSuccess, let cvTexture = cvTextureOut, let metalTex = CVMetalTextureGetTexture(cvTexture) {
                    let origin = MTLOrigin(x: 0, y: 0, z: 0)
                    let size = MTLSize(width: min(width, texture.width), height: min(height, texture.height), depth: 1)
                    
                    guard let commandBuffer = commandQueue.makeCommandBuffer(),
                          let blitEncoder = commandBuffer.makeBlitCommandEncoder() else { return }
                    
                    blitEncoder.copy(from: metalTex,
                                     sourceSlice: 0,
                                     sourceLevel: 0,
                                     sourceOrigin: origin,
                                     sourceSize: size,
                                     to: texture,
                                     destinationSlice: 0,
                                     destinationLevel: 0,
                                     destinationOrigin: origin)
                    blitEncoder.endEncoding()
                    commandBuffer.commit()
                    
                    CVMetalTextureCacheFlush(cache, 0)
                }
            }
        }
    }

    func stop() {
        if let dl = displayLink {
            CVDisplayLinkStop(dl)
        }
        displayLink = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        NotificationCenter.default.removeObserver(self)
        
        if let url = videoURL {
            DispatchQueue.global(qos: .background).async {
                try? FileManager.default.removeItem(at: url)
            }
            videoURL = nil
        }
        
        if let cache = textureCache {
            CVMetalTextureCacheFlush(cache, 0)
        }
    }

    deinit {
        stop()
    }
}
