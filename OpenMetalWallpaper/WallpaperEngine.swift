/*
 License: AGPLv3
 Author: laobamac
 File: WallpaperEngine.swift
 Description: Engine with stop-by-ID capability.
*/

import Cocoa
import AVFoundation
import WebKit

extension Notification.Name {
    static let wallpaperDidChange = Notification.Name("omw_wallpaper_did_change")
}

enum WallpaperScaleMode: Int, CaseIterable, Identifiable {
    case fill = 0
    case fit = 1
    case stretch = 2
    case custom = 3
    var id: Int { self.rawValue }
    var label: String {
        switch self {
        case .fill: return "填充 (Cover)"
        case .fit: return "适应 (Fit)"
        case .stretch: return "拉伸 (Stretch)"
        case .custom: return "自定义 (Custom)"
        }
    }
    var videoGravity: AVLayerVideoGravity {
        switch self {
        case .fill: return .resizeAspectFill
        case .fit: return .resizeAspect
        case .stretch: return .resize
        case .custom: return .resizeAspectFill
        }
    }
}

class ScreenController: NSObject {
    let screen: NSScreen
    var window: NSWindow?
    private var backgroundView: NSView!
    
    private var playerLayer: AVPlayerLayer?
    private var queuePlayer: AVQueuePlayer?
    private var singlePlayer: AVPlayer?
    private var looper: AVPlayerLooper?
    private var endObserver: NSObjectProtocol?
    private var resourceLoaderDelegate: MemoryResourceLoader?
    private var webView: WKWebView?
    
    var currentURL: URL?
    var currentWallpaperID: String?
    var isMemoryMode: Bool = false
    var isPlaying: Bool = false
    
    var volume: Float = 0.5 { didSet { updatePlayers(); saveSettings() } }
    var playbackRate: Float = 1.0 { didSet { if isPlaying { applyRate() }; saveSettings() } }
    var isLooping: Bool = true { didSet { saveSettings() } }
    var scaleMode: WallpaperScaleMode = .fill {
        didSet {
            playerLayer?.videoGravity = scaleMode.videoGravity
            if scaleMode != .custom { resetTransform() } else { updateLayerTransform() }
            saveSettings()
        }
    }
    var videoScale: CGFloat = 1.0 { didSet { if scaleMode == .custom { updateLayerTransform(); saveSettings() } } }
    var xOffset: CGFloat = 0.0 { didSet { if scaleMode == .custom { updateLayerTransform(); saveSettings() } } }
    var yOffset: CGFloat = 0.0 { didSet { if scaleMode == .custom { updateLayerTransform(); saveSettings() } } }
    
    init(screen: NSScreen) {
        self.screen = screen
        super.init()
        setupWindow()
    }
    
    private func setupWindow() {
        let screenRect = screen.frame
        let newWindow = NSWindow(contentRect: screenRect,
                                 styleMask: [.borderless],
                                 backing: .buffered,
                                 defer: false)
        newWindow.level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
        newWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        newWindow.backgroundColor = .black
        newWindow.hasShadow = false
        newWindow.isOpaque = true
        backgroundView = NSView(frame: NSRect(origin: .zero, size: screenRect.size))
        backgroundView.wantsLayer = true
        backgroundView.layer = CALayer()
        backgroundView.layer?.backgroundColor = NSColor.black.cgColor
        newWindow.contentView = backgroundView
        self.window = newWindow
        self.window?.makeKeyAndOrderFront(nil)
    }
    
    private func updatePlayers() { queuePlayer?.volume = volume; singlePlayer?.volume = volume }
    private func saveSettings() {
        guard let wId = currentWallpaperID else { return }
        let config = WallpaperConfig(volume: volume, playbackRate: playbackRate, scaleMode: scaleMode.rawValue, isLooping: isLooping, videoScale: videoScale, xOffset: xOffset, yOffset: yOffset)
        WallpaperPersistence.shared.save(config: config, monitor: screen.localizedName, wallpaperId: wId)
    }
    private func loadSettings(wallpaperId: String) {
        if let config = WallpaperPersistence.shared.load(monitor: screen.localizedName, wallpaperId: wallpaperId) {
            self.volume = config.volume; self.playbackRate = config.playbackRate; self.isLooping = config.isLooping
            self.scaleMode = WallpaperScaleMode(rawValue: config.scaleMode) ?? .fill
            self.videoScale = config.videoScale; self.xOffset = config.xOffset; self.yOffset = config.yOffset
        } else {
            self.volume = 0.5; self.playbackRate = 1.0; self.scaleMode = .fill
            self.isLooping = true; self.videoScale = 1.0; self.xOffset = 0; self.yOffset = 0
        }
    }
    
    func play(url: URL, wallpaperId: String, loadToMemory: Bool) {
        if window == nil { setupWindow() }
        stop(keepWindow: true)
        self.currentURL = url
        self.currentWallpaperID = wallpaperId
        self.isMemoryMode = loadToMemory
        self.isPlaying = true
        
        WallpaperPersistence.shared.saveActiveWallpaper(monitor: screen.localizedName, wallpaperId: wallpaperId)
        loadSettings(wallpaperId: wallpaperId)
        
        let ext = url.pathExtension.lowercased()
        if ext == "html" || ext == "htm" { playWeb(url: url) }
        else { if loadToMemory { playInMemory(url: url) } else { playFromDisk(url: url) } }
        
        NotificationCenter.default.post(name: .wallpaperDidChange, object: nil, userInfo: ["monitor": screen.localizedName])
    }
    
    private func playWeb(url: URL) {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        let wv = WKWebView(frame: backgroundView.bounds, configuration: config)
        wv.autoresizingMask = [.width, .height]
        wv.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        backgroundView.addSubview(wv)
        self.webView = wv
    }
    
    private func playFromDisk(url: URL) {
        let playerItem = AVPlayerItem(url: url)
        let player = AVQueuePlayer(playerItem: playerItem)
        player.volume = self.volume
        if isLooping { self.looper = AVPlayerLooper(player: player, templateItem: playerItem) }
        else { player.actionAtItemEnd = .pause }
        self.queuePlayer = player
        setupLayer(player: player)
        applyRate()
    }
    
    private func playInMemory(url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let ext = url.pathExtension.lowercased()
            let mimeType = ext == "webm" ? "video/webm" : "video/mp4"
            let loader = MemoryResourceLoader(data: data, contentType: mimeType)
            self.resourceLoaderDelegate = loader
            let customUrl = URL(string: "streaming-\(url.lastPathComponent)")!
            let asset = AVURLAsset(url: customUrl)
            asset.resourceLoader.setDelegate(loader, queue: DispatchQueue.main)
            let playerItem = AVPlayerItem(asset: asset)
            let player = AVPlayer(playerItem: playerItem)
            player.volume = self.volume
            self.singlePlayer = player
            if let oldObserver = endObserver { NotificationCenter.default.removeObserver(oldObserver) }
            self.endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main) { [weak self] _ in
                guard let self = self else { return }
                if self.isLooping { player.seek(to: .zero); self.applyRate() }
            }
            setupLayer(player: player)
            applyRate()
        } catch { print("Memory error: \(error)") }
    }
    
    private func setupLayer(player: AVPlayer) {
        playerLayer?.removeFromSuperlayer()
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = scaleMode.videoGravity
        layer.frame = backgroundView.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        backgroundView.layer?.addSublayer(layer)
        self.playerLayer = layer
        if scaleMode == .custom { updateLayerTransform() }
    }
    
    func updateLayerTransform() {
        guard let layer = playerLayer else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: xOffset, y: yOffset)
        transform = transform.scaledBy(x: videoScale, y: videoScale)
        layer.setAffineTransform(transform)
        CATransaction.commit()
    }
    
    func resetTransform() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        playerLayer?.setAffineTransform(.identity)
        CATransaction.commit()
    }
    
    func applyRate() { queuePlayer?.rate = playbackRate; singlePlayer?.rate = playbackRate }
    func pause() { queuePlayer?.pause(); singlePlayer?.pause() }
    func resume() { if isPlaying { applyRate() } }
    
    func stop(keepWindow: Bool = false) {
        isPlaying = false
        if !keepWindow { WallpaperPersistence.shared.saveActiveWallpaper(monitor: screen.localizedName, wallpaperId: nil) }
        queuePlayer?.pause(); queuePlayer = nil; looper = nil
        if let observer = endObserver { NotificationCenter.default.removeObserver(observer); endObserver = nil }
        singlePlayer?.pause(); singlePlayer = nil; resourceLoaderDelegate = nil
        playerLayer?.removeFromSuperlayer(); playerLayer = nil
        webView?.removeFromSuperview(); webView = nil
        if !keepWindow { window?.orderOut(nil); window = nil }
        NotificationCenter.default.post(name: .wallpaperDidChange, object: nil)
    }
}

class WallpaperEngine: NSObject {
    static let shared = WallpaperEngine()
    private var screenControllers: [String: ScreenController] = [:]
    private(set) var isGlobalPaused: Bool = false
    private var isSystemPaused: Bool = false
    var pauseOnAppFocus: Bool = UserDefaults.standard.bool(forKey: "omw_pauseOnAppFocus")
    
    var activeScreens: [String: String] {
        var status: [String: String] = [:]
        for (id, controller) in screenControllers {
            if controller.isPlaying { status[id] = controller.currentWallpaperID ?? "Unknown" }
        }
        return status
    }
    
    override init() {
        super.init()
        refreshScreens()
        NotificationCenter.default.addObserver(self, selector: #selector(refreshScreens), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appDidActivate), name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }
    
    @objc func refreshScreens() {
        for screen in NSScreen.screens {
            let id = screen.localizedName
            if screenControllers[id] == nil {
                screenControllers[id] = ScreenController(screen: screen)
            }
        }
    }
    
    func getController(for screen: NSScreen) -> ScreenController {
        let id = screen.localizedName
        if let controller = screenControllers[id] { return controller }
        let newController = ScreenController(screen: screen)
        screenControllers[id] = newController
        return newController
    }
    
    func play(url: URL, wallpaperId: String, screen: NSScreen, loadToMemory: Bool) {
        getController(for: screen).play(url: url, wallpaperId: wallpaperId, loadToMemory: loadToMemory)
        checkAppFocusState()
    }
    
    // --- 新增：根据 ID 停止正在播放的壁纸 ---
    func stopWallpaper(id: String) {
        for (_, controller) in screenControllers {
            if controller.currentWallpaperID == id {
                controller.stop()
            }
        }
    }
    
    func restoreSessions(library: WallpaperLibrary) {
        for (screenID, controller) in screenControllers {
            if let lastID = WallpaperPersistence.shared.loadActiveWallpaper(monitor: screenID) {
                if let wallpaper = library.wallpapers.first(where: { $0.id == lastID }),
                   let path = wallpaper.absolutePath {
                    let loadToMemory = UserDefaults.standard.bool(forKey: "omw_loadToMemory")
                    controller.play(url: path, wallpaperId: lastID, loadToMemory: loadToMemory)
                }
            }
        }
    }
    
    func stop(screen: NSScreen) { getController(for: screen).stop() }
    func togglePause() { isGlobalPaused.toggle(); screenControllers.values.forEach { isGlobalPaused ? $0.pause() : $0.resume() } }
    func updateSettings() { self.pauseOnAppFocus = UserDefaults.standard.bool(forKey: "omw_pauseOnAppFocus"); checkAppFocusState() }
    @objc func appDidActivate(_ notification: Notification) { checkAppFocusState() }
    
    private func checkAppFocusState() {
        guard pauseOnAppFocus, !isGlobalPaused else { return }
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let isFinder = app.bundleIdentifier == "com.apple.finder"
        let isMe = app.bundleIdentifier == Bundle.main.bundleIdentifier
        if isFinder || isMe { if isSystemPaused { isSystemPaused = false; screenControllers.values.forEach { if $0.isPlaying { $0.resume() } } } }
        else { if !isSystemPaused { isSystemPaused = true; screenControllers.values.forEach { $0.pause() } } }
    }
}
