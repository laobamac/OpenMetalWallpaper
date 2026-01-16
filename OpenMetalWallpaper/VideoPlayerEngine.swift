/*
 License: AGPLv3
 Author: laobamac
 File: VideoPlayerEngine.swift
 Description: Video Engine with Rotation support.
*/

import Cocoa
import AVFoundation

class VideoPlayerEngine: NSObject, WallpaperPlayer {
    private var playerLayer: AVPlayerLayer?
    private var queuePlayer: AVQueuePlayer?
    private var singlePlayer: AVPlayer?
    private var looper: AVPlayerLooper?
    private var resourceLoader: MemoryResourceLoader?
    private var endObserver: NSObjectProtocol?
    
    private weak var containerView: NSView?
    private var options: WallpaperOptions?
    
    func attach(to view: NSView) {
        self.containerView = view
    }
    
    func load(url: URL, options: WallpaperOptions) {
        self.options = options
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
        
        // 自定义模式下应用位移和缩放
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
}
