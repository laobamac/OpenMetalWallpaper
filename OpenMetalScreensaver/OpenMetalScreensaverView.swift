//
//  OpenMetalScreensaverView.swift
//  OpenMetalWallpaper
//
//  Created by laobamac on 2026/1/20.
//

import ScreenSaver
import WebKit
import AVFoundation

class DataResourceLoader: NSObject, AVAssetResourceLoaderDelegate {
    let data: Data
    let contentType: String
    
    init(data: Data, contentType: String) {
        self.data = data
        self.contentType = contentType
    }
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        if let contentRequest = loadingRequest.contentInformationRequest {
            contentRequest.contentType = self.contentType
            contentRequest.contentLength = Int64(data.count)
            contentRequest.isByteRangeAccessSupported = true
        }
        
        if let dataRequest = loadingRequest.dataRequest {
            let requestedOffset = Int(dataRequest.requestedOffset)
            let requestedLength = dataRequest.requestedLength
            let start = requestedOffset
            let end = min(requestedOffset + requestedLength, data.count)
            
            if start < data.count {
                let subdata = data.subdata(in: start..<end)
                dataRequest.respond(with: subdata)
                loadingRequest.finishLoading()
            }
        }
        return true
    }
}

class OpenMetalScreensaverView: ScreenSaverView {
    
    private var webView: WKWebView?
    private var playerLayer: AVPlayerLayer?
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var errorLabel: NSTextField?
    private var resourceLoader: DataResourceLoader?
    private var rateObservation: NSKeyValueObservation?
    private var useMemory: Bool = false
    
    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        self.animationTimeInterval = 1.0 / 30.0
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.black.cgColor
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.loadWallpaperConfig()
        }
    }
    
    private func getRealHomeDirectory() -> String {
        if let pw = getpwuid(getuid()) {
            return String(cString: pw.pointee.pw_dir)
        }
        return NSHomeDirectory()
    }
    
    private func loadWallpaperConfig() {
        let realHome = getRealHomeDirectory()
        let configPath = realHome + "/Library/Application Support/OpenMetalWallpaper/screensaver.json"
        
        if !FileManager.default.fileExists(atPath: configPath) {
            showError("未配置屏保\n请在 OpenMetalWallpaper 中右键壁纸\n选择“设置为动态屏保”")
            return
        }
        
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
            if let config = try JSONSerialization.jsonObject(with: data, options: []) as? [String: String],
               let pathStr = config["filePath"] {
                
                let memoryStr = config["loadToMemory"] ?? "false"
                self.useMemory = (memoryStr == "true")
                
                let url = URL(fileURLWithPath: pathStr)
                playMedia(url: url)
                
            } else {
                showError("配置文件损坏")
            }
        } catch {
            showError("无法读取配置: \(error.localizedDescription)")
        }
    }
    
    private func playMedia(url: URL) {
        cleanup()
        let ext = url.pathExtension.lowercased()
        
        if ["html", "htm", "php", "json"].contains(ext) {
            showError("屏保暂不支持该格式壁纸")
        } else {
            playVideo(url: url)
        }
    }
    
    private func playVideo(url: URL) {
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
        let shouldLoadToMemory = self.useMemory && (fileSize > 0 && fileSize < 500 * 1024 * 1024)
        
        Task {
            var asset: AVURLAsset
            
            if shouldLoadToMemory, let data = try? Data(contentsOf: url) {
                let ext = url.pathExtension.lowercased()
                let mime = ext == "webm" ? "video/webm" : "video/mp4"
                let loader = DataResourceLoader(data: data, contentType: mime)
                self.resourceLoader = loader
                
                asset = AVURLAsset(url: URL(string: "stream-omw-\(url.lastPathComponent)")!)
                asset.resourceLoader.setDelegate(loader, queue: .main)
            } else {
                asset = AVURLAsset(url: url)
            }
            
            let item = AVPlayerItem(asset: asset)
            
            if let composition = try? await AVMutableVideoComposition.videoComposition(withPropertiesOf: asset) {
                composition.frameDuration = CMTime(value: 1, timescale: 30)
                item.videoComposition = composition
            }
            
            await MainActor.run {
                self.setupPlayerItem(item)
            }
        }
    }
    
    private func setupPlayerItem(_ item: AVPlayerItem) {
        let queuePlayer = AVQueuePlayer(playerItem: item)
        queuePlayer.volume = 0.0
        queuePlayer.actionAtItemEnd = .none
        queuePlayer.automaticallyWaitsToMinimizeStalling = false
        
        self.looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        self.player = queuePlayer
        
        let layer = AVPlayerLayer(player: queuePlayer)
        layer.frame = self.bounds
        layer.videoGravity = .resizeAspectFill
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        
        self.layer?.addSublayer(layer)
        self.playerLayer = layer
        
        rateObservation = queuePlayer.observe(\.rate, options: [.new]) { [weak self] player, change in
            guard self != nil else { return }
            if abs(player.rate - 0.5) > 0.01 && player.rate != 0 {
                player.rate = 0.5
            }
        }
        
        queuePlayer.playImmediately(atRate: 0.5)
    }
    
    private func cleanup() {
        rateObservation?.invalidate()
        rateObservation = nil
        
        player?.pause()
        player = nil
        looper = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        
        webView?.removeFromSuperview()
        webView = nil
        resourceLoader = nil
        
        errorLabel?.removeFromSuperview()
        errorLabel = nil
    }
    
    private func showError(_ msg: String) {
        cleanup()
        let label = NSTextField(labelWithString: msg)
        label.textColor = .white
        label.alignment = .center
        label.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        label.drawsBackground = true
        label.backgroundColor = NSColor.black.withAlphaComponent(0.7)
        label.isBezeled = false
        label.isEditable = false
        label.isSelectable = false
        
        self.addSubview(label)
        self.errorLabel = label
        
        label.frame = self.bounds
        label.cell?.wraps = true
        label.cell?.isScrollable = false
    }
    
    override func startAnimation() {
        super.startAnimation()
        if let p = player {
            p.playImmediately(atRate: 0.5)
        }
    }
    
    override func stopAnimation() {
        super.stopAnimation()
        if let p = player { p.pause() }
    }
    
    override func draw(_ rect: NSRect) {
        super.draw(rect)
        NSColor.black.setFill()
        rect.fill()
    }
    
    override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize)
        playerLayer?.frame = self.bounds
    }
    
    override var hasConfigureSheet: Bool { return false }
}
