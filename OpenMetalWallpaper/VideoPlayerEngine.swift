/*
 License: AGPLv3
 Author: laobamac
 File: VideoPlayerEngine.swift
 Description: Video Player implementation updated for new Protocol.
*/

import Cocoa
import AVFoundation
import CoreImage

class VideoPlayerEngine: NSObject, WallpaperPlayer {
    private var playerLayer: AVPlayerLayer?
    private var queuePlayer: AVQueuePlayer?
    private var singlePlayer: AVPlayer?
    private var looper: AVPlayerLooper?
    private var resourceLoader: MemoryResourceLoader?
    private var endObserver: NSObjectProtocol?
    
    private weak var containerView: NSView?
    private var options: WallpaperOptions?
    private var currentURL: URL?
    
    // Core Image Context
    private let ciContext = CIContext()
    
    func attach(to view: NSView) {
        self.containerView = view
    }
    
    func load(url: URL, options: WallpaperOptions) {
        self.options = options
        self.currentURL = url
        stop()
        
        if options.isMemoryMode {
            playInMemory(url: url)
        } else {
            playFromDisk(url: url)
        }
    }
    
    private func playFromDisk(url: URL) {
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer(playerItem: item)
        player.volume = options?.volume ?? 0.5
        
        // Apply Composition (FPS + Filters)
        applyComposition(to: item)
        
        if options?.isLooping == true {
            self.looper = AVPlayerLooper(player: player, templateItem: item)
        } else {
            player.actionAtItemEnd = .pause
        }
        
        self.queuePlayer = player
        setupLayer(player: player)
        applyRate()
    }
    
    private func playInMemory(url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let ext = url.pathExtension.lowercased()
            let mime = ext == "webm" ? "video/webm" : "video/mp4"
            let loader = MemoryResourceLoader(data: data, contentType: mime)
            self.resourceLoader = loader
            
            let asset = AVURLAsset(url: URL(string: "stream-\(url.lastPathComponent)")!)
            asset.resourceLoader.setDelegate(loader, queue: .main)
            
            let item = AVPlayerItem(asset: asset)
            
            // Apply Composition (FPS + Filters)
            applyComposition(to: item)
            
            let player = AVPlayer(playerItem: item)
            player.volume = options?.volume ?? 0.5
            self.singlePlayer = player
            
            if let obs = endObserver { NotificationCenter.default.removeObserver(obs) }
            self.endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                if self?.options?.isLooping == true {
                    player.seek(to: .zero)
                    player.rate = self?.options?.playbackRate ?? 1.0
                }
            }
            
            setupLayer(player: player)
            applyRate()
        } catch { print("Video load error: \(error)") }
    }
    
    // Combined logic for FPS limit and Post-Processing filters
    private func applyComposition(to item: AVPlayerItem) {
        guard let opts = self.options else { return }
        
        let needsFilters = (opts.brightness != 0 || opts.contrast != 1 || opts.saturation != 1)
        let needsFps = (opts.fpsLimit > 0 && opts.fpsLimit < 60)
        
        if !needsFilters && !needsFps {
            item.videoComposition = nil
            return
        }
        
        Task {
            do {
                let asset = item.asset
                // Creating a composition from properties can be tricky async, simplistic approach here:
                // Note: For robust filter + fps support, one usually needs a custom compositor or careful mutable composition construction.
                // This is kept simplified as per original logic structure.
                let composition = try await AVMutableVideoComposition.videoComposition(withPropertiesOf: asset)
                
                // Apply FPS Limit
                if needsFps {
                    composition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(opts.fpsLimit))
                }
                
                // Apply Filters if needed
                if needsFilters {
                    let b = opts.brightness
                    let c = opts.contrast
                    let s = opts.saturation
                    
                    composition.customVideoCompositorClass = nil
                    
                    let filterComposition = AVVideoComposition(asset: asset) { [weak self] request in
                        guard let self = self else { request.finish(with: request.sourceImage, context: nil); return }
                        
                        let source = request.sourceImage.clampedToExtent()
                        let filter = CIFilter(name: "CIColorControls")
                        filter?.setValue(source, forKey: kCIInputImageKey)
                        filter?.setValue(b, forKey: kCIInputBrightnessKey)
                        filter?.setValue(c, forKey: kCIInputContrastKey)
                        filter?.setValue(s, forKey: kCIInputSaturationKey)
                        
                        let output = filter?.outputImage?.cropped(to: request.sourceImage.extent) ?? source
                        request.finish(with: output, context: self.ciContext)
                    }
                    
                    if let mutableComp = filterComposition.mutableCopy() as? AVMutableVideoComposition {
                        if needsFps {
                            mutableComp.frameDuration = CMTime(value: 1, timescale: CMTimeScale(opts.fpsLimit))
                        }
                        await MainActor.run { item.videoComposition = mutableComp }
                    }
                } else {
                    await MainActor.run { item.videoComposition = composition }
                }
                
            } catch {
                print("Composition error: \(error)")
            }
        }
    }
    
    func setFrameLimit(_ fps: Int) {
        self.options?.fpsLimit = fps
        refreshComposition()
    }
    
    func setPostProcessing(brightness: Float, contrast: Float, saturation: Float) {
        self.options?.brightness = brightness
        self.options?.contrast = contrast
        self.options?.saturation = saturation
        refreshComposition()
    }
    
    private func refreshComposition() {
        if let qp = queuePlayer, let item = qp.currentItem {
            applyComposition(to: item)
        } else if let sp = singlePlayer, let item = sp.currentItem {
            applyComposition(to: item)
        }
    }
    
    private func setupLayer(player: AVPlayer) {
        guard let view = containerView else { return }
        playerLayer?.removeFromSuperlayer()
        
        let layer = AVPlayerLayer(player: player)
        layer.frame = view.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer?.addSublayer(layer)
        self.playerLayer = layer
        
        if let opts = options {
            updateScaling(mode: opts.scaleMode, scale: opts.videoScale, x: opts.xOffset, y: opts.yOffset, rotation: opts.rotation)
        }
    }
    
    func snapshot(completion: @escaping (NSImage?) -> Void) {
        guard let url = self.currentURL else { completion(nil); return }
        Task {
            let asset = AVAsset(url: url)
            do {
                let tracks = try await asset.loadTracks(withMediaType: .video)
                guard tracks.count > 0 else { await MainActor.run { completion(nil) }; return }
            } catch { await MainActor.run { completion(nil) }; return }

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .positiveInfinity
            generator.requestedTimeToleranceAfter = .positiveInfinity
            
            let time = CMTime(seconds: 0.5, preferredTimescale: 600)
            do {
                let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
                let size = NSSize(width: cgImage.width, height: cgImage.height)
                let nsImage = NSImage(cgImage: cgImage, size: size)
                await MainActor.run { completion(nsImage) }
            } catch {
                 await MainActor.run { completion(nil) }
            }
        }
    }
    
    func stop() {
        queuePlayer?.pause(); queuePlayer = nil
        looper = nil
        singlePlayer?.pause(); singlePlayer = nil
        resourceLoader = nil
        if let obs = endObserver { NotificationCenter.default.removeObserver(obs) }
        playerLayer?.removeFromSuperlayer(); playerLayer = nil
    }
    
    func pause() { queuePlayer?.pause(); singlePlayer?.pause() }
    func resume() { applyRate() }
    
    private func applyRate() {
        let rate = options?.playbackRate ?? 1.0
        queuePlayer?.rate = rate
        singlePlayer?.rate = rate
    }
    
    func setVolume(_ volume: Float) {
        options?.volume = volume
        queuePlayer?.volume = volume
        singlePlayer?.volume = volume
    }
    
    func setPlaybackRate(_ rate: Float) {
        options?.playbackRate = rate
        applyRate()
    }
    
    func setMute(_ muted: Bool) {
        let vol = muted ? 0 : (options?.volume ?? 0.5)
        queuePlayer?.volume = vol
        singlePlayer?.volume = vol
    }
    
    func setBackgroundColor(_ color: NSColor) {
        if let view = containerView {
            view.layer?.backgroundColor = color.cgColor
        }
    }
    
    func updateScaling(mode: WallpaperScaleMode, scale: CGFloat, x: CGFloat, y: CGFloat, rotation: Int) {
        options?.scaleMode = mode
        options?.videoScale = scale
        options?.xOffset = x
        options?.yOffset = y
        options?.rotation = rotation
        
        guard let layer = playerLayer else { return }
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.videoGravity = mode.videoGravity
        
        var transform = CGAffineTransform.identity
        
        if mode == .custom {
            transform = transform.translatedBy(x: x, y: y)
            transform = transform.scaledBy(x: scale, y: scale)
        }
        
        if rotation != 0 {
            let radians = CGFloat(rotation) * .pi / 180.0
            transform = transform.rotated(by: radians)
        }
        
        layer.setAffineTransform(transform)
        CATransaction.commit()
    }
    
    // MARK: - Protocol Updates for Web Support
    // 视频壁纸不需要这些功能，提供空实现以满足协议
    
    func updateProperties(_ properties: [String : Any]) {
        // Video player ignores generic properties
    }
    
    func sendAudioData(_ audioArray: [Float]) {
        // Video player does not support audio visualization
    }
}
