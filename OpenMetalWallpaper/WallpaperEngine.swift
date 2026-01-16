/*
 License: AGPLv3
 Author: laobamac
 File: WallpaperEngine.swift
 Description: Manager with Strict Pause Enforcement (Fixes Auto-Resume on Edit).
*/

import Cocoa
import AVFoundation
import WebKit

extension Notification.Name {
    static let wallpaperDidChange = Notification.Name("omw_wallpaper_did_change")
    static let globalPauseDidChange = Notification.Name("omw_global_pause_did_change")
}

extension NSView {
    func findFirstScrollView() -> NSScrollView? {
        if let self = self as? NSScrollView { return self }
        for subview in subviews {
            if let found = subview.findFirstScrollView() { return found }
        }
        return nil
    }
}

enum WallpaperScaleMode: Int, CaseIterable, Identifiable {
    case fill = 0, fit = 1, stretch = 2, custom = 3
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .fill: return NSLocalizedString("fill_mode", comment: "")
        case .fit: return NSLocalizedString("fit_mode", comment: "")
        case .stretch: return NSLocalizedString("stretch_mode", comment: "")
        case .custom: return NSLocalizedString("custom_mode", comment: "")
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
    var screen: NSScreen
    var window: NSWindow?
    private var backgroundView: NSView!
    private var currentPlayer: WallpaperPlayer?
    
    var currentURL: URL?
    var currentWallpaperID: String?
    var isPlaying: Bool = false
    var isMemoryMode: Bool = false
    private var isLoading: Bool = false
    
    // --- 属性监听 (核心修复：防止修改属性导致自动播放) ---
    // --- Property monitoring (Core fix: prevents autoplay caused by property modification) ---
    
    var volume: Float = 0.5 {
        didSet {
            // 音量可以随时改，不影响播放状态
            // The volume can be adjusted at any time without affecting playback.
            self.currentPlayer?.setVolume(self.volume)
            saveSettings()
        }
    }
    
    var playbackRate: Float = 1.0 {
        didSet {
            // 核心修复：如果当前是全局暂停状态，严禁设置播放器速率！
            // Core fix: If currently in global pause state, strictly prohibit setting player rate!
            // 因为 AVPlayer.rate = 1.0 会自动触发播放。
            // Because AVPlayer.rate = 1.0 will automatically trigger playback.
            if !WallpaperEngine.shared.isGlobalPaused && isPlaying {
                self.currentPlayer?.setPlaybackRate(self.playbackRate)
            }
            saveSettings()
        }
    }
    
    var isLooping: Bool = true { didSet { saveSettings() } }
    
    var scaleMode: WallpaperScaleMode = .fill { didSet { self.updatePlayerScaling(); saveSettings() } }
    var videoScale: CGFloat = 1.0 { didSet { if scaleMode == .custom { self.updatePlayerScaling() }; saveSettings() } }
    var xOffset: CGFloat = 0.0 { didSet { if scaleMode == .custom { self.updatePlayerScaling() }; saveSettings() } }
    var yOffset: CGFloat = 0.0 { didSet { if scaleMode == .custom { self.updatePlayerScaling() }; saveSettings() } }
    var rotation: Int = 0 { didSet { self.updatePlayerScaling(); saveSettings() } }
    
    var backgroundColor: NSColor = .black {
        didSet {
            runOnMain {
                self.backgroundView.layer?.backgroundColor = self.backgroundColor.cgColor
                self.currentPlayer?.setBackgroundColor(self.backgroundColor)
            }
            saveSettings()
        }
    }
    
    init(screen: NSScreen) {
        self.screen = screen
        super.init()
        runOnMain { self.setupWindow() }
    }
    
    private func runOnMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
    }
    
    private func setupWindow() {
        let screenRect = screen.frame
        let newWindow = NSWindow(contentRect: screenRect, styleMask: [.borderless], backing: .buffered, defer: false)
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
    
    private func updatePlayerScaling() {
        guard !isLoading else { return }
        runOnMain {
            self.currentPlayer?.updateScaling(mode: self.scaleMode, scale: self.videoScale, x: self.xOffset, y: self.yOffset, rotation: self.rotation)
        }
    }
    
    private func colorToString(_ color: NSColor) -> String {
        guard let rgb = color.usingColorSpace(.sRGB) else { return "0,0,0" }
        return "\(rgb.redComponent),\(rgb.greenComponent),\(rgb.blueComponent)"
    }
    private func stringToColor(_ str: String) -> NSColor {
        let parts = str.split(separator: ",").compactMap { Double($0) }
        if parts.count >= 3 { return NSColor(srgbRed: parts[0], green: parts[1], blue: parts[2], alpha: 1.0) }
        return .black
    }
    
    private func saveSettings() {
        guard !isLoading, let wId = currentWallpaperID else { return }
        let config = WallpaperConfig(
            volume: volume, playbackRate: playbackRate, scaleMode: scaleMode.rawValue, isLooping: isLooping,
            videoScale: videoScale, xOffset: xOffset, yOffset: yOffset,
            backgroundColor: colorToString(backgroundColor), rotation: rotation
        )
        WallpaperPersistence.shared.save(config: config, monitor: screen.localizedName, wallpaperId: wId)
    }
    
    // --- 恢复默认设置 ---
    // --- Restore default settings ---
    func resetSettings() {
        self.isLoading = true
        
        // 重置内部状态 - Reset internal state
        self.volume = 0.5
        self.playbackRate = 1.0
        self.isLooping = true
        self.scaleMode = .fill
        self.videoScale = 1.0
        self.xOffset = 0.0
        self.yOffset = 0.0
        self.rotation = 0
        self.backgroundColor = .black
        
        runOnMain {
            // 应用状态到播放器 - Application status to player
            self.currentPlayer?.setVolume(0.5)
            self.currentPlayer?.setBackgroundColor(.black)
            self.currentPlayer?.updateScaling(mode: .fill, scale: 1.0, x: 0, y: 0, rotation: 0)
            
            // 核心修复：只有在未暂停时才应用速率，防止自动播放
            // Core fix: Only apply rate when not paused to prevent autoplay
            if !WallpaperEngine.shared.isGlobalPaused {
                self.currentPlayer?.setPlaybackRate(1.0)
            } else {
                // 如果是暂停状态，确保它真的停住了
                // If it's paused, make sure it's actually stopped.
                self.currentPlayer?.pause()
            }
        }
        
        self.isLoading = false
        self.saveSettings()
        
        NotificationCenter.default.post(name: .wallpaperDidChange, object: nil, userInfo: ["monitor": self.screen.localizedName])
    }
    
    private func loadSettings(wallpaperId: String) {
        if let config = WallpaperPersistence.shared.load(monitor: screen.localizedName, wallpaperId: wallpaperId) {
            self.volume = config.volume; self.playbackRate = config.playbackRate; self.isLooping = config.isLooping
            self.scaleMode = WallpaperScaleMode(rawValue: config.scaleMode) ?? .fill
            self.videoScale = config.videoScale; self.xOffset = config.xOffset; self.yOffset = config.yOffset
            self.backgroundColor = stringToColor(config.backgroundColor ?? "0,0,0")
            self.rotation = config.rotation
        } else {
            self.volume = 0.5; self.playbackRate = 1.0; self.scaleMode = .fill
            self.isLooping = true; self.videoScale = 1.0; self.xOffset = 0; self.yOffset = 0; self.backgroundColor = .black; self.rotation = 0
        }
    }
    
    func play(url: URL, wallpaperId: String, loadToMemory: Bool) {
        DispatchQueue.main.async {
            self.isLoading = true
            if self.window == nil { self.setupWindow() }
            self._stop(keepWindow: true)
            
            self.rotation = 0; self.scaleMode = .fill; self.volume = 0.5
            self.currentURL = url; self.currentWallpaperID = wallpaperId; self.isMemoryMode = loadToMemory; self.isPlaying = true
            
            WallpaperPersistence.shared.saveActiveWallpaper(monitor: self.screen.localizedName, wallpaperId: wallpaperId)
            self.loadSettings(wallpaperId: wallpaperId)
            
            let ext = url.pathExtension.lowercased()
            let player: WallpaperPlayer
            if ["html", "htm"].contains(ext) { player = WebPlayerEngine() } else { player = VideoPlayerEngine() }
            
            player.attach(to: self.backgroundView)
            
            let options = WallpaperOptions(
                isMemoryMode: loadToMemory, isLooping: self.isLooping, volume: self.volume, playbackRate: self.playbackRate,
                scaleMode: self.scaleMode, videoScale: self.videoScale, xOffset: self.xOffset, yOffset: self.yOffset,
                backgroundColor: self.backgroundColor, rotation: self.rotation
            )
            
            player.load(url: url, options: options)
            self.currentPlayer = player
            
            // 初始检查：如果全局暂停，立即停止
            // Initial check: If the global system is paused, stop immediately.
            if WallpaperEngine.shared.isGlobalPaused {
                player.pause()
            }
            
            self.isLoading = false
            NotificationCenter.default.post(name: .wallpaperDidChange, object: nil, userInfo: ["monitor": self.screen.localizedName])
        }
    }
    
    func stop(keepWindow: Bool = false) { DispatchQueue.main.async { self._stop(keepWindow: keepWindow) } }
    
    private func _stop(keepWindow: Bool) {
        self.isPlaying = false
        if !keepWindow { WallpaperPersistence.shared.saveActiveWallpaper(monitor: self.screen.localizedName, wallpaperId: nil) }
        currentPlayer?.stop(); currentPlayer = nil
        if !keepWindow { window?.orderOut(nil); window = nil }
        NotificationCenter.default.post(name: .wallpaperDidChange, object: nil)
    }
    
    // --- 控制逻辑 ---
    // --- Control Logic ---
    func pause() {
        runOnMain { self.currentPlayer?.pause() }
    }
    
    func resume() {
        runOnMain {
            self.currentPlayer?.resume()
            // 恢复播放时，重新应用速率，因为之前可能被 pause 覆盖了
            // When resuming playback, reapply the rate, as it may have been overridden by pause before
            self.currentPlayer?.setPlaybackRate(self.playbackRate)
        }
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
        for (id, controller) in screenControllers { if controller.isPlaying { status[id] = controller.currentWallpaperID ?? "Unknown" } }
        return status
    }
    
    override init() {
        super.init()
        refreshScreens()
        NotificationCenter.default.addObserver(self, selector: #selector(refreshScreens), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appDidActivate), name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }
    
    @objc func refreshScreens() {
        DispatchQueue.main.async {
            let currentScreens = NSScreen.screens
            let currentScreenIDs = Set(currentScreens.map { $0.localizedName })
            let disconnectedIDs = self.screenControllers.keys.filter { !currentScreenIDs.contains($0) }
            for id in disconnectedIDs {
                self.screenControllers[id]?.stop(keepWindow: false)
                self.screenControllers.removeValue(forKey: id)
            }
            for screen in currentScreens {
                let id = screen.localizedName
                if self.screenControllers[id] == nil { self.screenControllers[id] = ScreenController(screen: screen) }
                else { self.screenControllers[id]?.screen = screen }
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
    
    func play(url: URL, wallpaperId: String, screen: NSScreen, loadToMemory: Bool) { getController(for: screen).play(url: url, wallpaperId: wallpaperId, loadToMemory: loadToMemory); checkAppFocusState() }
    func stopWallpaper(id: String) { DispatchQueue.main.async { for (_, c) in self.screenControllers { if c.currentWallpaperID == id { c.stop() } } } }
    func restoreSessions(library: WallpaperLibrary) { DispatchQueue.main.async { for (screenID, controller) in self.screenControllers { if let lastID = WallpaperPersistence.shared.loadActiveWallpaper(monitor: screenID) { if let wallpaper = library.wallpapers.first(where: { $0.id == lastID }), let path = wallpaper.absolutePath { let loadToMemory = UserDefaults.standard.bool(forKey: "omw_loadToMemory"); controller.play(url: path, wallpaperId: lastID, loadToMemory: loadToMemory) } } } } }
    func stop(screen: NSScreen) { getController(for: screen).stop() }
    
    // --- 切换全局暂停 ---
    func togglePause() {
        isGlobalPaused.toggle()
        DispatchQueue.main.async {
            self.screenControllers.values.forEach { self.isGlobalPaused ? $0.pause() : $0.resume() }
            // 通知 UI 刷新按钮
            // Notify UI to refresh button
            NotificationCenter.default.post(name: .globalPauseDidChange, object: nil)
        }
    }
    
    func updateSettings() { self.pauseOnAppFocus = UserDefaults.standard.bool(forKey: "omw_pauseOnAppFocus"); checkAppFocusState() }
    @objc func appDidActivate(_ notification: Notification) { checkAppFocusState() }
    private func checkAppFocusState() { guard pauseOnAppFocus, !isGlobalPaused else { return }; guard let app = NSWorkspace.shared.frontmostApplication else { return }; let isFinder = app.bundleIdentifier == "com.apple.finder"; let isMe = app.bundleIdentifier == Bundle.main.bundleIdentifier; DispatchQueue.main.async { if isFinder || isMe { if self.isSystemPaused { self.isSystemPaused = false; self.screenControllers.values.forEach { if $0.isPlaying { $0.resume() } } } } else { if !self.isSystemPaused { self.isSystemPaused = true; self.screenControllers.values.forEach { $0.pause() } } } } }
}
