//
//  WallpaperEngine.swift
//  OpenMetalWallpaper
//
//  Created by laobamac on 2026/1/17.
//

import Cocoa
import AVFoundation

class ClickBlockingView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let view = super.hitTest(point)
        return view == self ? self : view
    }
    
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}
}

class GlobalEventMonitor {
    private var monitor: Any?
    
    func start(handler: @escaping (NSEvent) -> Void) {
        stop()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp, .leftMouseDragged, .mouseMoved]
        monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
    }
    
    func stop() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

class AccessibilityUtils {
    static func isTrusted() -> Bool {
        return AXIsProcessTrusted()
    }
    
    static func promptForPermissions() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String : true]
        AXIsProcessTrustedWithOptions(options)
    }
}

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
        case .custom: return .resizeAspect
        }
    }
}

class WallpaperWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

class ScreenController: NSObject {
    var screen: NSScreen
    var window: NSWindow?
    private var backgroundView: NSView!
    private var mouseBlocker: ClickBlockingView?
    private(set) var currentPlayer: WallpaperPlayer?
    var currentURL: URL?
    var currentWallpaperID: String?
    var isPlaying: Bool = false
    var isMemoryMode: Bool = false
    private var isLoading: Bool = false
    private var isBatchUpdating: Bool = false
    private var lastLockScreenURL: URL?
    
    var volume: Float = 0.5 { didSet { if !isBatchUpdating { self.currentPlayer?.setVolume(self.volume); saveSettings() } } }
    var playbackRate: Float = 1.0 { didSet { if !isBatchUpdating { if !WallpaperEngine.shared.isGlobalPaused && isPlaying { self.currentPlayer?.setPlaybackRate(self.playbackRate) }; saveSettings() } } }
    var isLooping: Bool = true { didSet { if !isBatchUpdating { saveSettings() } } }
    var scaleMode: WallpaperScaleMode = .fill { didSet { if !isBatchUpdating { self.updatePlayerScaling(); saveSettings() } } }
    var videoScale: CGFloat = 1.0 { didSet { if !isBatchUpdating { if scaleMode == .custom { self.updatePlayerScaling() }; saveSettings() } } }
    var xOffset: CGFloat = 0.0 { didSet { if !isBatchUpdating { if scaleMode == .custom { self.updatePlayerScaling() }; saveSettings() } } }
    var yOffset: CGFloat = 0.0 { didSet { if !isBatchUpdating { if scaleMode == .custom { self.updatePlayerScaling() }; saveSettings() } } }
    var rotation: Int = 0 { didSet { if !isBatchUpdating { self.updatePlayerScaling(); saveSettings() } } }
    var backgroundColor: NSColor = .black
    var brightness: Float = 0.0 { didSet { if !isBatchUpdating { self.updatePostProcessing(); saveSettings() } } }
    var contrast: Float = 1.0 { didSet { if !isBatchUpdating { self.updatePostProcessing(); saveSettings() } } }
    var saturation: Float = 1.0 { didSet { if !isBatchUpdating { self.updatePostProcessing(); saveSettings() } } }
    
    var webProperties: [String: Any] = [:] {
        didSet {
            if !isBatchUpdating {
                self.currentPlayer?.updateProperties(webProperties)
                saveSettings()
            }
        }
    }
    
    var isInteractive: Bool = false {
        didSet {
            if !isBatchUpdating {
                self.updateWindowInteraction()
                saveSettings()
                WallpaperEngine.shared.checkGlobalEventMonitorState()
            }
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
        let newWindow = WallpaperWindow(contentRect: screenRect, styleMask: [.borderless], backing: .buffered, defer: false)
        newWindow.level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
        newWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        newWindow.backgroundColor = .black
        newWindow.hasShadow = false
        newWindow.isOpaque = true
        newWindow.ignoresMouseEvents = true
            
        backgroundView = NSView(frame: NSRect(origin: .zero, size: screenRect.size))
        backgroundView.wantsLayer = true
        backgroundView.layer = CALayer()
        backgroundView.layer?.backgroundColor = NSColor.black.cgColor
        
        let blocker = ClickBlockingView(frame: backgroundView.bounds)
        blocker.autoresizingMask = [.width, .height]
        blocker.isHidden = true
        backgroundView.addSubview(blocker)
        self.mouseBlocker = blocker
        
        newWindow.contentView = backgroundView
        self.window = newWindow
        self.window?.orderFront(nil)
        updateIconVisibility()
    }
        
    func updateWindowInteraction() {
        runOnMain {
            let shouldAcceptEvents = self.isInteractive || WallpaperEngine.shared.areIconsHidden
            self.window?.ignoresMouseEvents = !shouldAcceptEvents
            self.mouseBlocker?.isHidden = self.isInteractive
            self.currentPlayer?.setInteractive(self.isInteractive)
            if let blocker = self.mouseBlocker, blocker.superview != nil {
                self.backgroundView.addSubview(blocker, positioned: .above, relativeTo: nil)
            }
        }
    }
        
    func updateIconVisibility() {
        runOnMain {
            let hideIcons = WallpaperEngine.shared.areIconsHidden
            if hideIcons {
                self.window?.level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            } else {
                self.window?.level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
            }
            self.updateWindowInteraction()
        }
    }
    
    private func updatePlayerScaling() {
        guard !isLoading else { return }
        runOnMain { self.currentPlayer?.updateScaling(mode: self.scaleMode, scale: self.videoScale, x: self.xOffset, y: self.yOffset, rotation: self.rotation) }
    }
    
    func updateFrameLimit(_ fps: Int) {
        runOnMain { self.currentPlayer?.setFrameLimit(fps) }
    }
    
    func setPostProcessing(brightness: Float, contrast: Float, saturation: Float) {
        isBatchUpdating = true
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
        isBatchUpdating = false
        self.updatePostProcessing()
        self.saveSettings()
    }
    
    private func updatePostProcessing() {
        guard !isLoading else { return }
        runOnMain { self.currentPlayer?.setPostProcessing(brightness: self.brightness, contrast: self.contrast, saturation: self.saturation) }
    }
    
    func updateWebProperty(key: String, value: Any) {
        webProperties[key] = value
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
        if !webProperties.isEmpty {
             UserDefaults.standard.set(webProperties, forKey: "omw_props_\(wId)_\(screen.localizedName)")
        }
        let config = WallpaperConfig(
                volume: volume, playbackRate: playbackRate, scaleMode: scaleMode.rawValue, isLooping: isLooping,
                videoScale: videoScale, xOffset: xOffset, yOffset: yOffset,
                backgroundColor: colorToString(backgroundColor), rotation: rotation,
                brightness: brightness, contrast: contrast, saturation: saturation,
                isInteractive: isInteractive
            )
            WallpaperPersistence.shared.save(config: config, monitor: screen.localizedName, wallpaperId: wId)
        }
    
    func resetSettings() {
        self.isLoading = true
        self.isBatchUpdating = true
        self.volume = 0.5; self.playbackRate = 1.0; self.isLooping = true
        self.scaleMode = .fill; self.videoScale = 1.0; self.xOffset = 0.0; self.yOffset = 0.0; self.rotation = 0
        self.backgroundColor = .black
        self.brightness = 0.0; self.contrast = 1.0; self.saturation = 1.0
        self.webProperties = [:]
        self.isBatchUpdating = false
        
        runOnMain {
            self.currentPlayer?.setVolume(0.5)
            self.currentPlayer?.setBackgroundColor(.black)
            self.currentPlayer?.updateScaling(mode: .fill, scale: 1.0, x: 0, y: 0, rotation: 0)
            self.currentPlayer?.setPostProcessing(brightness: 0, contrast: 1, saturation: 1)
            self.currentPlayer?.updateProperties([:])
            
            if !WallpaperEngine.shared.isGlobalPaused { self.currentPlayer?.setPlaybackRate(1.0) }
            else { self.currentPlayer?.pause() }
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
            self.backgroundColor = stringToColor(config.backgroundColor ?? "0,0,0"); self.rotation = config.rotation
            self.brightness = config.brightness; self.contrast = config.contrast; self.saturation = config.saturation
            self.isInteractive = config.isInteractive
        } else {
            self.volume = 0.5; self.playbackRate = 1.0; self.scaleMode = .fill; self.isLooping = true
            self.videoScale = 1.0; self.xOffset = 0; self.yOffset = 0; self.backgroundColor = .black; self.rotation = 0
            self.brightness = 0.0; self.contrast = 1.0; self.saturation = 1.0
            self.isInteractive = false
        }
        
        if let props = UserDefaults.standard.dictionary(forKey: "omw_props_\(wallpaperId)_\(screen.localizedName)") {
            self.webProperties = props
        } else {
            self.webProperties = [:]
        }
    }
    
    func play(url: URL, wallpaperId: String, wallpaperType: String, loadToMemory: Bool, defaultProperties: [String: Any]) {
        DispatchQueue.main.async {
            self.isLoading = true
            if self.window == nil { self.setupWindow() }
            self._stop(keepWindow: true)
            
            self.isBatchUpdating = true
            self.rotation = 0; self.scaleMode = .fill; self.volume = 0.5
            self.webProperties = defaultProperties
            self.isBatchUpdating = false
            
            self.currentURL = url; self.currentWallpaperID = wallpaperId; self.isMemoryMode = loadToMemory; self.isPlaying = true
            
            WallpaperPersistence.shared.saveActiveWallpaper(monitor: self.screen.localizedName, wallpaperId: wallpaperId, filePath: url)
            self.loadSettings(wallpaperId: wallpaperId)
            
            let player: WallpaperPlayer
            if wallpaperType == "web" {
                player = WebPlayerEngine()
            } else if wallpaperType == "scene" {
                player = ScenePlayerEngine()
            } else {
                player = VideoPlayerEngine()
            }
            
            player.attach(to: self.backgroundView)
            
            if let blocker = self.mouseBlocker {
                blocker.removeFromSuperview()
                self.backgroundView.addSubview(blocker)
            }
            
            let fpsLimit = UserDefaults.standard.integer(forKey: "omw_fpsLimit")
            let safeFps = fpsLimit == 0 ? 60 : fpsLimit
            
            let options = WallpaperOptions(
                isMemoryMode: loadToMemory, isLooping: self.isLooping, volume: self.volume, playbackRate: self.playbackRate,
                scaleMode: self.scaleMode, videoScale: self.videoScale, xOffset: self.xOffset, yOffset: self.yOffset,
                backgroundColor: self.backgroundColor, rotation: self.rotation, fpsLimit: safeFps,
                brightness: self.brightness, contrast: self.contrast, saturation: self.saturation,
                isInteractive: self.isInteractive,
                userProperties: self.webProperties
            )
            
            player.load(url: url, options: options)
            self.currentPlayer = player
            
            self.updateWindowInteraction()
            self.updateIconVisibility()
            
            if WallpaperEngine.shared.isGlobalPaused { player.pause() }
            
            self.isLoading = false
            NotificationCenter.default.post(name: .wallpaperDidChange, object: nil, userInfo: ["monitor": self.screen.localizedName])
            NotificationCenter.default.post(name: Notification.Name("omw_restore_focus"), object: nil)
            WallpaperEngine.shared.checkGlobalEventMonitorState()
            
            if UserDefaults.standard.bool(forKey: "omw_overrideLockScreen") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    guard let self = self, self.currentWallpaperID == wallpaperId else { return }
                    self.currentPlayer?.snapshot { [weak self] image in
                        guard let self = self, let img = image else { return }
                        self.setSystemWallpaper(image: img)
                    }
                }
            }
        }
    }
    
    private func setSystemWallpaper(image: NSImage) {
        let tempDir = FileManager.default.temporaryDirectory
        let safeName = screen.localizedName.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        let prefix = "omw_lock_\(safeName)_"
        let fileManager = FileManager.default
            
        let uniqueID = UUID().uuidString
        let filename = "\(prefix)\(uniqueID).png"
        let newURL = tempDir.appendingPathComponent(filename)
        self.lastLockScreenURL = newURL
                
        if let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let pngData = bitmap.representation(using: .png, properties: [:]) {
            do {
                try pngData.write(to: newURL)
                try NSWorkspace.shared.setDesktopImageURL(newURL, for: self.screen, options: [:])
                    
                DispatchQueue.global(qos: .utility).async {
                    if let files = try? fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil) {
                        for fileURL in files {
                            let fname = fileURL.lastPathComponent
                            if fname.hasPrefix(prefix) && fname != filename {
                                try? fileManager.removeItem(at: fileURL)
                            }
                        }
                    }
                }
            } catch { }
        }
    }
    
    func stop(keepWindow: Bool = false) { DispatchQueue.main.async { self._stop(keepWindow: keepWindow) } }
    
    private func _stop(keepWindow: Bool) {
        self.isPlaying = false
        if !keepWindow { WallpaperPersistence.shared.saveActiveWallpaper(monitor: self.screen.localizedName, wallpaperId: nil, filePath: nil) }
        currentPlayer?.stop(); currentPlayer = nil
        if !keepWindow { window?.orderOut(nil); window = nil }
        NotificationCenter.default.post(name: .wallpaperDidChange, object: nil)
        WallpaperEngine.shared.checkGlobalEventMonitorState()
    }
    
    func pause() { runOnMain { self.currentPlayer?.pause() } }
    
    func resume() { runOnMain { self.currentPlayer?.resume(); self.currentPlayer?.setPlaybackRate(self.playbackRate) } }
}

class WallpaperEngine: NSObject {
    static let shared = WallpaperEngine()
    private var screenControllers: [String: ScreenController] = [:]
    private(set) var isGlobalPaused: Bool = false
    private var isSystemPaused: Bool = false
    var pauseOnAppFocus: Bool = UserDefaults.standard.bool(forKey: "omw_pauseOnAppFocus")
    private(set) var areIconsHidden: Bool = false
    private let eventMonitor = GlobalEventMonitor()
    
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
            for id in disconnectedIDs { self.screenControllers[id]?.stop(keepWindow: false); self.screenControllers.removeValue(forKey: id) }
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
    
    func play(url: URL, wallpaperId: String, wallpaperType: String, screen: NSScreen, loadToMemory: Bool, defaultProperties: [String: Any]) {
        getController(for: screen).play(url: url, wallpaperId: wallpaperId, wallpaperType: wallpaperType, loadToMemory: loadToMemory, defaultProperties: defaultProperties)
        checkAppFocusState()
    }
    
    func stopWallpaper(id: String) {
        DispatchQueue.main.async {
            for (_, c) in self.screenControllers { if c.currentWallpaperID == id { c.stop() } }
        }
    }
    
    func toggleHideIcons() {
        areIconsHidden.toggle()
        screenControllers.values.forEach { $0.updateIconVisibility() }
        checkGlobalEventMonitorState()
    }
    
    func restoreSessions(library: WallpaperLibrary) {
        self.refreshScreens()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            for (screenID, controller) in self.screenControllers {
                if let lastID = WallpaperPersistence.shared.loadActiveWallpaper(monitor: screenID) {
                    if let wallpaper = library.wallpapers.first(where: { $0.id == lastID }), let path = wallpaper.absolutePath {
                        let loadToMemory = UserDefaults.standard.bool(forKey: "omw_loadToMemory")
                        let type = wallpaper.type?.lowercased() ?? "video"
                        var defaultProps: [String: Any] = [:]
                        if let props = wallpaper.general?.properties {
                            for (key, config) in props {
                                if let val = config.value {
                                    defaultProps[key] = val.rawValue
                                }
                            }
                        }
                        controller.play(url: path, wallpaperId: lastID, wallpaperType: type, loadToMemory: loadToMemory, defaultProperties: defaultProps)
                    }
                }
            }
            self.checkAppFocusState()
            if !self.isGlobalPaused && !self.isSystemPaused { self.screenControllers.values.forEach { if $0.isPlaying { $0.resume() } } }
        }
    }
    
    func stop(screen: NSScreen) { getController(for: screen).stop() }
    
    func togglePause() {
        isGlobalPaused.toggle()
        DispatchQueue.main.async {
            self.screenControllers.values.forEach { self.isGlobalPaused ? $0.pause() : $0.resume() }
            NotificationCenter.default.post(name: .globalPauseDidChange, object: nil)
        }
    }
    
    func updateSettings() {
        self.pauseOnAppFocus = UserDefaults.standard.bool(forKey: "omw_pauseOnAppFocus")
        let newFps = UserDefaults.standard.integer(forKey: "omw_fpsLimit")
        let safeFps = newFps == 0 ? 60 : newFps
        self.screenControllers.values.forEach { $0.updateFrameLimit(safeFps) }
        checkAppFocusState()
    }
    
    @objc func appDidActivate(_ notification: Notification) { checkAppFocusState() }
    
    private func checkAppFocusState() {
            guard pauseOnAppFocus, !isGlobalPaused else { return }
            guard let app = NSWorkspace.shared.frontmostApplication else { return }
            let isFinder = app.bundleIdentifier == "com.apple.finder"
            let isMe = app.bundleIdentifier == Bundle.main.bundleIdentifier
            DispatchQueue.main.async {
                if isFinder || isMe {
                    if self.isSystemPaused { self.isSystemPaused = false; self.screenControllers.values.forEach { if $0.isPlaying { $0.resume() } } }
                } else {
                    if !self.isSystemPaused { self.isSystemPaused = true; self.screenControllers.values.forEach { $0.pause() } }
                }
            }
        }
    
    func checkGlobalEventMonitorState() {
        let needGlobal = !areIconsHidden && screenControllers.values.contains { $0.isInteractive && $0.isPlaying }
        if needGlobal {
            if AccessibilityUtils.isTrusted() {
                eventMonitor.start { [weak self] event in self?.handleGlobalEvent(event) }
            } else {
                eventMonitor.stop()
            }
        } else {
            eventMonitor.stop()
        }
    }
    
    private func handleGlobalEvent(_ event: NSEvent) {
        let mouseLoc = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) }) else { return }
        let screenId = screen.localizedName
        guard let controller = screenControllers[screenId], controller.isInteractive, controller.isPlaying else { return }
        let screenFrame = screen.frame
        let localX = mouseLoc.x - screenFrame.origin.x
        let localY = screenFrame.height - (mouseLoc.y - screenFrame.origin.y)
        
        if let webPlayer = controller.currentPlayer as? WebPlayerEngine {
            var eventTypes: [String] = []
            switch event.type {
            case .leftMouseDown:
                eventTypes = ["mousedown"]
            case .leftMouseUp:
                eventTypes = ["mouseup", "click"]
            case .leftMouseDragged, .mouseMoved:
                eventTypes = ["mousemove"]
            default:
                return
            }
            let typesToSend = eventTypes
            DispatchQueue.main.async {
                for type in typesToSend {
                    webPlayer.injectMouseEvent(type: type, x: localX, y: localY)
                }
            }
        }
    }
}
