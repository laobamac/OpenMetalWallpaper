/*
 File: ContentView.swift
 Description: Main UI with Screensaver Alert & Context Menu.
*/

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var library: WallpaperLibrary
    
    // Navigation & Selection
    @State private var selectedCategory: String? = "installed"
    @State private var selectedWallpaper: WallpaperProject?
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var monitors: [Monitor] = Monitor.getAll()
    @State private var selectedMonitor: Monitor? = Monitor.getAll().first
    
    // UI State
    @State private var showSettings = false
    @State private var isImporting = false
    @State private var isGlobalPaused: Bool = false
    @State private var showNewWallpaperSheet = false
    @State private var pendingVideoURL: URL?
    @State private var newWallpaperName: String = ""
    @State private var showImportAlert = false
    @State private var importStatusMessage = ""
    @State private var isProcessingImport = false
    
    // Icon Hiding State
    @State private var areIconsHidden: Bool = false
    
    // [New] Screensaver Success Alert
    @State private var showScreensaverSetAlert: Bool = false
    
    // Settings Link
    @AppStorage("omw_loadToMemory") private var loadToMemory: Bool = false
    
    var filteredWallpapers: [WallpaperProject] {
        guard let category = selectedCategory else { return library.wallpapers }
        if category == "workshop" {
            return library.wallpapers.filter { $0.absolutePath?.path.contains("steamapps") ?? false }
        }
        return library.wallpapers
    }
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selectedCategory: $selectedCategory)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220)
                .background(
                    VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                        .ignoresSafeArea()
                )
        } content: {
            ZStack {
                // Main Background
                VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Monitor Picker
                    MonitorPickerHeader(monitors: monitors, selectedMonitor: $selectedMonitor, refreshAction: refreshMonitors)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    
                    // Wallpaper Grid
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 240), spacing: 16)], spacing: 16) {
                            if filteredWallpapers.isEmpty {
                                Text("")
                            } else {
                                ForEach(filteredWallpapers) { wallpaper in
                                    WallpaperCard(wallpaper: wallpaper)
                                        .onTapGesture {
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                                self.selectedWallpaper = wallpaper
                                                applyWallpaper(wallpaper)
                                            }
                                        }
                                        // MARK: - Context Menu
                                        .contextMenu {
                                            Button(NSLocalizedString("show_in_finder", comment: "")) {
                                                if let path = wallpaper.absolutePath { NSWorkspace.shared.activateFileViewerSelecting([path]) }
                                            }
                                            
                                            // Set as Screensaver (Video Only)
                                            if (wallpaper.type?.lowercased() ?? "video") == "video" {
                                                Button(action: {
                                                    if let path = wallpaper.absolutePath {
                                                        WallpaperPersistence.shared.setScreensaverConfig(
                                                            wallpaperId: wallpaper.id,
                                                            filePath: path,
                                                            loadToMemory: loadToMemory
                                                        )
                                                        // [New] Trigger Alert
                                                        showScreensaverSetAlert = true
                                                    }
                                                }) {
                                                    Label("设置为动态屏保", systemImage: "display.2")
                                                }
                                            }
                                            
                                            Divider()
                                            
                                            Button(NSLocalizedString("remove_from_list", comment: "")) {
                                                stopWallpaper(wallpaper.id)
                                                library.removeWallpaper(id: wallpaper.id, deleteFile: false)
                                                if selectedWallpaper?.id == wallpaper.id { selectedWallpaper = nil }
                                            }
                                            
                                            Button(NSLocalizedString("delete_wallpaper_file", comment: ""), role: .destructive) {
                                                stopWallpaper(wallpaper.id)
                                                library.removeWallpaper(id: wallpaper.id, deleteFile: true)
                                                if selectedWallpaper?.id == wallpaper.id { selectedWallpaper = nil }
                                            }
                                        }
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.accentColor, lineWidth: selectedWallpaper?.id == wallpaper.id ? 4 : 0)
                                                .animation(.easeInOut(duration: 0.2), value: selectedWallpaper?.id)
                                        )
                                }
                            }
                        }
                        .padding()
                        .animation(.easeInOut(duration: 0.3), value: selectedCategory)
                    }
                    .overlay {
                        if filteredWallpapers.isEmpty {
                            EmptyStateView(isImporting: $isImporting)
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        }
                    }
                    
                    Divider()
                    
                    // Bottom Toolbar
                    HStack(spacing: 16) {
                        Button(action: { isImporting = true }) { Label(NSLocalizedString("add_button", comment: ""), systemImage: "plus") }
                        Divider().frame(height: 20)
                        Button(action: toggleGlobalPause) { Image(systemName: isGlobalPaused ? "play.fill" : "pause.fill").font(.title2) }
                            .buttonStyle(.borderless)
                        Button(action: stopCurrentMonitor) { Label(NSLocalizedString("stop_button", comment: ""), systemImage: "square.fill") }
                        
                        // Hide/Show Icons Button
                        Button(action: toggleIcons) {
                            Label(areIconsHidden ? NSLocalizedString("show_icons", comment: "Show Icons") : NSLocalizedString("hide_icons", comment: "Hide Icons"),
                                  systemImage: areIconsHidden ? "eye.slash.fill" : "eye.fill")
                        }
                        .help(NSLocalizedString("hide_icons_help", comment: "Hide Desktop Icons"))
                        
                        Spacer()
                        if isProcessingImport { ProgressView().controlSize(.small).padding(.trailing) }
                        Button(action: { showSettings = true }) { Label(NSLocalizedString("settings_button", comment: ""), systemImage: "gearshape") }
                    }
                    .padding()
                    .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow))
                }
            }
            .edgesIgnoringSafeArea(.top)
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in handleDrop(providers: providers) }
            
        } detail: {
            ZStack {
                VisualEffectView(material: .contentBackground, blendingMode: .behindWindow)
                    .ignoresSafeArea()
                
                if let wallpaper = selectedWallpaper, let monitor = selectedMonitor {
                    WallpaperInspector(wallpaper: wallpaper, monitor: monitor)
                        .id(wallpaper.id)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .animation(.easeInOut(duration: 0.3), value: wallpaper.id)
                } else {
                    Text(NSLocalizedString("select_wallpaper_message", comment: ""))
                        .foregroundColor(.secondary)
                        .font(.title2)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        
        // [New] Screensaver Success Alert
        .alert("设置成功", isPresented: $showScreensaverSetAlert) {
            Button("好的", role: .cancel) { }
        } message: {
            Text("该视频已设置为动态屏保。\n请在“系统设置 -> 屏幕保护程序”中选择 OpenMetalScreensaver 即可预览。")
        }
        
        // Existing Alerts
        .alert("Import Status", isPresented: $showImportAlert) { Button("OK", role: .cancel) { } } message: { Text(importStatusMessage) }
        
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.folder], allowsMultipleSelection: true) { result in
            if let urls = try? result.get() {
                for url in urls { guard url.startAccessingSecurityScopedResource() else { continue } }
                handleBatchImport(urls: urls)
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showNewWallpaperSheet) {
            VStack(spacing: 20) {
                Text(NSLocalizedString("new_video_wallpaper_title", comment: "")).font(.headline)
                TextField(NSLocalizedString("wallpaper_name_placeholder", comment: ""), text: $newWallpaperName).textFieldStyle(.roundedBorder).frame(width: 300)
                HStack {
                    Button(NSLocalizedString("cancel_button", comment: "")) { showNewWallpaperSheet = false; pendingVideoURL = nil }.keyboardShortcut(.cancelAction)
                    Button(NSLocalizedString("create_button", comment: "")) {
                        if let url = pendingVideoURL {
                            let name = newWallpaperName
                            showNewWallpaperSheet = false; isProcessingImport = true
                            DispatchQueue.global().async {
                                let success = library.importVideoFile(url: url, title: name)
                                DispatchQueue.main.async { isProcessingImport = false; pendingVideoURL = nil; importStatusMessage = success ? "Video wallpaper imported." : "Failed."; showImportAlert = true }
                            }
                        }
                    }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                }
            }.padding().frame(width: 350, height: 150)
        }
        .onAppear { if selectedMonitor == nil { selectedMonitor = monitors.first }; syncSelection() }
        .onChange(of: selectedMonitor) { syncSelection() }
        .onReceive(NotificationCenter.default.publisher(for: .wallpaperDidChange)) { _ in syncSelection() }
        .onReceive(NotificationCenter.default.publisher(for: .globalPauseDidChange)) { _ in self.isGlobalPaused = WallpaperEngine.shared.isGlobalPaused }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("omw_icons_hidden_changed"))) { _ in
            self.areIconsHidden = WallpaperEngine.shared.areIconsHidden
        }
    }
    
    // MARK: - Logic Helpers
    
    private func toggleIcons() {
        WallpaperEngine.shared.toggleHideIcons()
        self.areIconsHidden = WallpaperEngine.shared.areIconsHidden
        NotificationCenter.default.post(name: Notification.Name("omw_icons_hidden_changed"), object: nil)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var urlsToProcess: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (urlData, error) in
                if let urlData = urlData as? Data, let url = URL(dataRepresentation: urlData, relativeTo: nil) {
                    urlsToProcess.append(url)
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { self.handleBatchImport(urls: urlsToProcess) }
        return true
    }
    
    private func handleBatchImport(urls: [URL]) {
        var newOnes: [URL] = []
        for url in urls {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
                if isDir.boolValue {
                    newOnes.append(url)
                } else if ["mp4", "webm", "mov", "m4v"].contains(url.pathExtension.lowercased()) {
                    self.pendingVideoURL = url
                    self.newWallpaperName = url.deletingPathExtension().lastPathComponent
                    self.showNewWallpaperSheet = true
                }
            }
        }
        if !newOnes.isEmpty {
            isProcessingImport = true
            DispatchQueue.global().async {
                for url in newOnes { self.library.importFromFolder(url: url) }
                DispatchQueue.main.async {
                    self.isProcessingImport = false
                    self.importStatusMessage = NSLocalizedString("import_success_message", comment: "")
                    self.showImportAlert = true
                }
            }
        }
    }
    
    private func syncSelection() {
        guard let monitor = selectedMonitor?.screen else { return }
        let controller = WallpaperEngine.shared.getController(for: monitor)
        if let currentId = controller.currentWallpaperID { if let wallpaper = library.wallpapers.first(where: { $0.id == currentId }) { self.selectedWallpaper = wallpaper } }
        self.isGlobalPaused = WallpaperEngine.shared.isGlobalPaused
    }
    
    private func refreshMonitors() { monitors = Monitor.getAll(); if !monitors.contains(where: { $0.id == selectedMonitor?.id }) { selectedMonitor = monitors.first } }
    
    private func applyWallpaper(_ wallpaper: WallpaperProject) {
        guard let monitor = selectedMonitor?.screen, let path = wallpaper.absolutePath else { return }
        var defaultProps: [String: Any] = [:]
        if let props = wallpaper.general?.properties { for (key, config) in props { if let val = config.value { defaultProps[key] = val.rawValue } } }
        WallpaperEngine.shared.play(url: path, wallpaperId: wallpaper.id, wallpaperType: wallpaper.type?.lowercased() ?? "video", screen: monitor, loadToMemory: loadToMemory, defaultProperties: defaultProps)
        self.isGlobalPaused = WallpaperEngine.shared.isGlobalPaused
    }
    
    private func stopWallpaper(_ id: String) {
        if let monitor = selectedMonitor?.screen {
            let controller = WallpaperEngine.shared.getController(for: monitor)
            if controller.currentWallpaperID == id { WallpaperEngine.shared.stop(screen: monitor) }
        }
    }
    
    private func toggleGlobalPause() { WallpaperEngine.shared.togglePause() }
    
    private func stopCurrentMonitor() { guard let monitor = selectedMonitor?.screen else { return }; WallpaperEngine.shared.stop(screen: monitor); self.selectedWallpaper = nil; self.isGlobalPaused = false }
}
