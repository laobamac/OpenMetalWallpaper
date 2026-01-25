//
//  OpenMetalWallpaperApp.swift
//  OpenMetalWallpaper
//
//  Created by laobamac on 2026/1/17.
//

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
        // Detect main window early
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
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.findAndSetupMainWindow()
            
            if let lib = self.library {
                print("Restoring sessions...")
                WallpaperEngine.shared.restoreSessions(library: lib)
            }
            
            // Check if launched as a login item (inactive)
            if !NSApp.isActive {
                print("Silent launch detected.")
                self.hideMainWindow()
            } else {
                self.openMainWindow()
            }
        }
    }
    
    func hideMainWindow() {
        if let window = self.mainWindow {
            window.orderOut(nil)
        }
        NSApp.setActivationPolicy(.accessory) // Hide from dock
    }
    
    @objc func openMainWindow() {
        // Important: Switch policy back to regular to show in Dock and accept focus properly
        NSApp.setActivationPolicy(.regular)
        
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            
            self.findAndSetupMainWindow()
            
            if let window = self.mainWindow {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
                window.deminiaturize(nil)
            } else {
                // Fallback: If window reference is lost (rare in SwiftUI WindowGroup), try to reactivate the App scene
                // SwiftUI doesn't give direct access to create new windows easily from AppDelegate,
                // but usually the window is just hidden, not destroyed.
                print("Main window reference missing, attempting generic activation.")
            }
        }
    }
    
    func findAndSetupMainWindow() {
        if let current = self.mainWindow, current.isVisible || current.occlusionState.contains(.visible) {
            return
        }
        
        // Filter windows to find the main SwiftUI window
        let candidates = NSApp.windows.filter { $0.styleMask.contains(.titled) && $0.identifier?.rawValue != "WallpaperWindow" && !($0 is NSPanel) }
        
        if let found = candidates.first {
            self.mainWindow = found
            found.delegate = self
            found.isReleasedWhenClosed = false
        }
    }
    
    @objc func detectMainWindow(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window.styleMask.contains(.titled) &&
           window.identifier?.rawValue != "WallpaperWindow" &&
           !(window is NSPanel) {
            self.mainWindow = window
            window.delegate = self
            window.isReleasedWhenClosed = false
        }
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender == mainWindow {
            self.hideMainWindow()
            return false // Prevent actual closing, just hide
        }
        return true
    }
    
    @objc func statusBarClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            let menu = buildMenu()
            statusBarItem.menu = menu // Attach menu temporarily
            statusBarItem.button?.performClick(nil) // Trigger menu
            statusBarItem.menu = nil // Detach to allow left click custom action next time
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
