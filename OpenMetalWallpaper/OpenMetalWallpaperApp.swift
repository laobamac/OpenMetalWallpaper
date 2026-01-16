/*
 License: AGPLv3
 Author: laobamac
 File: OpenMetalWallpaperApp.swift
 Description: App entry with Fixed Window Re-activation.
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

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let lib = self.library {
                WallpaperEngine.shared.restoreSessions(library: lib)
            }
        }
    }
    
    @objc func detectMainWindow(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window.styleMask.contains(.titled) {
            self.mainWindow = window
            window.delegate = self
        }
    }
    
    // 拦截关闭 - Blocking and closing
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === mainWindow {
            NSApp.setActivationPolicy(.accessory) // 隐藏 - Hide from Dock
            sender.orderOut(nil) // 隐藏窗口 - Hide window
            return false // 阻止销毁 - Prevent destruction
        }
        return true
    }
    
    @objc func openMainWindow() {
        NSApp.setActivationPolicy(.regular) // 显示 - Show in Dock
        NSApp.activate(ignoringOtherApps: true) // 前台 - Bring to foreground
        
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
        } else {
            // 兜底查找 - Bottom-line search
            if let found = NSApp.windows.first(where: { $0.styleMask.contains(.titled) }) {
                self.mainWindow = found
                found.delegate = self
                found.makeKeyAndOrderFront(nil)
            }
        }
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
