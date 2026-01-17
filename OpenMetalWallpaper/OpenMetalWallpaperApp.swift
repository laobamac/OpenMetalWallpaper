/*
 License: AGPLv3
 Author: laobamac
 File: OpenMetalWallpaperApp.swift
 Description: App entry with Fixed Window Re-activation & Silent Launch Support.
*/

import SwiftUI

@main
struct OpenMetalWallpaperApp: App {
    @StateObject var library = WallpaperLibrary()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .preferredColorScheme(.dark)
                .onAppear {
                    appDelegate.library = library
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands { SidebarCommands() }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var statusBarItem: NSStatusItem!
    var library: WallpaperLibrary?
    weak var mainWindow: NSWindow?
    private var isRestoringSessions = false // Prevent duplicate restoration / 防止重复恢复

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Listen for window activation to capture main window reference / 监听窗口激活，以便捕捉主窗口引用
        NotificationCenter.default.addObserver(self, selector: #selector(detectMainWindow(_:)), name: NSWindow.didBecomeKeyNotification, object: nil)
        
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusBarItem.button {
            if let logo = NSImage(named: "AppIcon") {
                button.image = logo.resized(to: NSSize(width: 22, height: 22))
            } else {
                button.image = NSImage(systemSymbolName: "cpu", accessibilityDescription: "OMW")
            }
            button.action = #selector(statusBarClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        if UserDefaults.standard.bool(forKey: "omw_checkUpdateOnStartup") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                UpdateChecker.shared.checkForUpdates(userInitiated: false)
            }
        }
        
        // Slightly extend delay to ensure screens and system services are ready / 稍微延长延迟，确保屏幕和系统服务已就绪
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.findAndSetupMainWindow()
            
            if let lib = self.library {
                print("开始恢复壁纸会话... / Start restoring wallpaper sessions")
                WallpaperEngine.shared.restoreSessions(library: lib)
            }
            
            // If NSApp.isActive is false, it means silent startup/login item / 如果 NSApp.isActive 为 false，说明是静默启动/开机自启
            if !NSApp.isActive {
                print("检测到后台启动，隐藏主界面 / Detected background startup, hiding main window")
                self.hideMainWindow()
            } else {
                // If manually double-clicked to launch, ensure window is in front / 如果是手动双击启动，确保窗口在前
                self.openMainWindow()
            }
        }
    }
    
    
    func hideMainWindow() {
        if let window = self.mainWindow {
            window.orderOut(nil)
        }
        // Only switch policy when actually hidden to prevent flickering / 只有真正隐藏了才切换策略，防止闪烁
        NSApp.setActivationPolicy(.accessory)
    }
    
    @objc func openMainWindow() {
        NSApp.setActivationPolicy(.regular)
        
        DispatchQueue.main.async {
            // Activate App / 激活 App
            NSApp.activate(ignoringOtherApps: true)
            
            // Try to find or reuse window / 尝试查找或复用窗口
            self.findAndSetupMainWindow()
            
            if let window = self.mainWindow {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
                window.deminiaturize(nil)
            } else {
                print("未找到主窗口引用，尝试通过 App 激活 / Main window reference not found, trying to activate via App")
            }
        }
    }
    
    func findAndSetupMainWindow() {
        // If reference is still valid, return directly / 如果引用还在且有效，直接返回
        if let current = self.mainWindow, current.isVisible || current.occlusionState.contains(.visible) {
            return
        }
        
        let candidates = NSApp.windows.filter { $0.styleMask.contains(.titled) && $0.identifier?.rawValue != "WallpaperWindow" }
        
        if let found = candidates.first {
            self.mainWindow = found
            found.delegate = self
            found.isReleasedWhenClosed = false // Disable release / 禁止释放
        }
    }
    
    
    @objc func detectMainWindow(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        
        // Filter out system panels (About panel, alerts, etc.) and other non-main windows
        // Only capture windows that are our main app window, not system dialogs
        if window.styleMask.contains(.titled) && 
           window.identifier?.rawValue != "WallpaperWindow" &&
           !(window is NSPanel) {
            self.mainWindow = window
            window.delegate = self
            window.isReleasedWhenClosed = false
        }
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Only intercept closing for our main window, not system panels (About, alerts, etc.)
        if sender.styleMask.contains(.titled) && 
           sender.identifier?.rawValue != "WallpaperWindow" &&
           !(sender is NSPanel) &&
           sender == mainWindow {
            self.hideMainWindow()
            return false
        }
        return true
    }
    
    @objc func statusBarClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent!
        if event.type == .rightMouseUp {
            let menu = buildMenu()
            statusBarItem.menu = menu
            statusBarItem.button?.performClick(nil)
            statusBarItem.menu = nil
        } else {
            openMainWindow()
        }
    }
    
    func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let verItem = NSMenuItem(title: "OpenMetalWallpaper \(AppInfo.fullVersionString)", action: nil, keyEquivalent: "")
        verItem.isEnabled = false
        menu.addItem(verItem)
        menu.addItem(NSMenuItem.separator())
        
        let activeScreens = WallpaperEngine.shared.activeScreens
        if activeScreens.isEmpty {
            let item = NSMenuItem(title: NSLocalizedString("no_playing_wallpaper", comment: ""), action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            for (screen, wallpaperId) in activeScreens {
                let title = library?.wallpapers.first(where: { $0.id == wallpaperId })?.title ?? "Unknown"
                let truncatedTitle = title.count > 20 ? String(title.prefix(20)) + "..." : title
                let item = NSMenuItem(title: "\(screen): \(truncatedTitle)", action: nil, keyEquivalent: "")
                item.isEnabled = false
                item.indentationLevel = 1
                menu.addItem(item)
            }
        }
        menu.addItem(NSMenuItem.separator())
        let isPaused = WallpaperEngine.shared.isGlobalPaused
        menu.addItem(withTitle: isPaused ? NSLocalizedString("resume_all", comment: "") : NSLocalizedString("pause_all", comment: ""), action: #selector(togglePause), keyEquivalent: "p")
        menu.addItem(withTitle: NSLocalizedString("open_main_window", comment: ""), action: #selector(openMainWindow), keyEquivalent: "o")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: NSLocalizedString("check_updates_menu", comment: ""), action: #selector(checkUpdates), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: NSLocalizedString("quit_app", comment: ""), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }
    
    @objc func togglePause() { WallpaperEngine.shared.togglePause() }
    @objc func checkUpdates() { UpdateChecker.shared.checkForUpdates(userInitiated: true) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { return false }
}

extension NSImage {
    func resized(to newSize: NSSize) -> NSImage? {
       if let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(newSize.width), pixelsHigh: Int(newSize.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) {
            bitmapRep.size = newSize
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
            self.draw(in: NSRect(x: 0, y: 0, width: newSize.width, height: newSize.height), from: .zero, operation: .copy, fraction: 1.0)
            NSGraphicsContext.restoreGraphicsState()
            
            let resizedImage = NSImage(size: newSize)
            resizedImage.addRepresentation(bitmapRep)
            return resizedImage
        }
        return nil
    }
}
