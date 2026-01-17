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
    private var currentURL: URL?
    
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
    
    func snapshot(completion: @escaping (NSImage?) -> Void) {
        guard let url = self.currentURL else { completion(nil); return }
        
        Task {
            let asset = AVAsset(url: url)
            // Ensure video track exists / 确保视频轨道存在
            do {
                let tracks = try await asset.loadTracks(withMediaType: .video)
                guard tracks.count > 0 else {
                    print("Snapshot failed: No video tracks found")
                    await MainActor.run { completion(nil) }
                    return
                }
            } catch {
                print("Snapshot failed: Unable to load video tracks - \(error)")
                await MainActor.run { completion(nil) }
                return
            }

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            
            // Important: Relax time tolerance to prevent failure due to lack of exact keyframes / 重要：放宽时间容差，防止因为没有精确的关键帧而失败
            generator.requestedTimeToleranceBefore = .positiveInfinity
            generator.requestedTimeToleranceAfter = .positiveInfinity
            
            // Try to get frame at 0.5 seconds (easier to avoid opening black screen than 0.1) / 尝试获取 0.5 秒处的帧（比 0.1 更容易避开片头黑屏）
            let time = CMTime(seconds: 0.5, preferredTimescale: 600)
            
            do {
                let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
                let size = NSSize(width: cgImage.width, height: cgImage.height)
                // Fix: Must specify Size, cannot use .zero, otherwise NSWorkspace may not recognize / 修复：必须指定 Size，不能用 .zero，否则 NSWorkspace 可能无法识别
                let nsImage = NSImage(cgImage: cgImage, size: size)
                await MainActor.run { completion(nsImage) }
            } catch {
                print("Snapshot at 0.5s failed: \(error). Trying 0.0s...")
                // Fallback: Try to get frame 0 / 回退：尝试获取第 0 帧
                do {
                    let zeroTime = CMTime.zero
                    let cgImage = try generator.copyCGImage(at: zeroTime, actualTime: nil)
                    let size = NSSize(width: cgImage.width, height: cgImage.height)
                    let nsImage = NSImage(cgImage: cgImage, size: size)
                    await MainActor.run { completion(nsImage) }
                } catch {
                    print("Snapshot failed completely: \(error)")
                    await MainActor.run { completion(nil) }
                }
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
}
