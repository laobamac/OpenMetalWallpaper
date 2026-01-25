//
//  ContentView.swift
//  OpenMetalWallpaper
//
//  Created by laobamac on 2026/1/17.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var library: WallpaperLibrary
    
    @State private var selectedCategory: String? = "installed"
    @State private var selectedWallpaper: WallpaperProject?
    @State private var selectedWorkshopItem: SteamWorkshopItem?
    
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var monitors: [Monitor] = Monitor.getAll()
    @State private var selectedMonitor: Monitor? = Monitor.getAll().first
    
    @State private var showSettings = false
    @State private var isImporting = false
    @State private var isGlobalPaused: Bool = false
    @State private var importProgressText: String = ""
    @State private var showImportAlert = false
    @State private var importStatusMessage = ""
    @State private var isProcessingImport = false
    @State private var areIconsHidden: Bool = false
    @State private var showScreensaverSetAlert: Bool = false
    
    @State private var showNewWallpaperSheet = false
    @State private var pendingVideoURL: URL?
    @State private var newWallpaperName: String = ""
    
    @State private var localSortOption: LocalSortOption = .name
    @State private var localFilterType: LocalFilterType = .all
    
    @AppStorage("omw_loadToMemory") private var loadToMemory: Bool = false
    
    enum LocalSortOption { case name, date }
    enum LocalFilterType { case all, scene, video, web }
    
    var filteredWallpapers: [WallpaperProject] {
        var items = library.wallpapers
        
        switch localFilterType {
        case .scene: items = items.filter { $0.type?.lowercased() == "scene" }
        case .video: items = items.filter { $0.type?.lowercased() == "video" }
        case .web: items = items.filter { $0.type?.lowercased() == "web" }
        case .all: break
        }
        
        switch localSortOption {
        case .name: items.sort { $0.title < $1.title }
        case .date: items.sort { $0.title > $1.title }
        }
        
        return items
    }
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VStack(spacing: 0) {
                List(selection: $selectedCategory) {
                    Section(header: Text("壁纸库")) {
                        Label("已安装", systemImage: "externaldrive.fill")
                            .tag("installed")
                    }
                    Section(header: Text("发现")) {
                        Label("创意工坊", systemImage: "globe")
                            .tag("workshop")
                    }
                }
                .listStyle(.sidebar)
                
                Spacer()
                
                VStack(alignment: .leading, spacing: 10) {
                    Divider()
                    Link(destination: URL(string: "https://github.com/laobamac/OpenMetalWallpaper")!) {
                        HStack(alignment: .center, spacing: 12) {
                            if let logoImage = NSImage(named: "AppLogo") {
                                Image(nsImage: logoImage).resizable().aspectRatio(contentMode: .fit).frame(width: 40, height: 40)
                            } else {
                                Image(nsImage: NSApp.applicationIconImage).resizable().aspectRatio(contentMode: .fit).frame(width: 40, height: 40)
                            }
                            VStack(alignment: .leading, spacing: 0) {
                                Text("OpenMetalWallpaper").font(.system(size: 13, weight: .bold)).foregroundColor(.primary).lineLimit(1)
                                Text("By laobamac").font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                    
                    HStack {
                        Text("License: AGPLv3").font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(4).background(Color.gray.opacity(0.2)).cornerRadius(4)
                        Spacer()
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow).ignoresSafeArea())
            
        } content: {
            ZStack {
                VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow).ignoresSafeArea()
                
                if selectedCategory == "workshop" {
                    WorkshopView(selectedItem: $selectedWorkshopItem).transition(.opacity)
                } else {
                    VStack(spacing: 0) {
                        MonitorPickerHeader(monitors: monitors, selectedMonitor: $selectedMonitor, refreshAction: refreshMonitors)
                            .padding(.horizontal).padding(.vertical, 8)
                        
                        HStack {
                            Picker("排序", selection: $localSortOption) {
                                Text("名称").tag(LocalSortOption.name)
                                Text("最近").tag(LocalSortOption.date)
                            }.pickerStyle(.menu).frame(width: 100)
                            
                            Picker("筛选", selection: $localFilterType) {
                                Text("全部").tag(LocalFilterType.all)
                                Text("场景").tag(LocalFilterType.scene)
                                Text("视频").tag(LocalFilterType.video)
                                Text("网页").tag(LocalFilterType.web)
                            }.pickerStyle(.menu).frame(width: 100)
                            
                            Spacer()
                        }
                        .padding(.horizontal)
                        
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 240), spacing: 16)], spacing: 16) {
                                if filteredWallpapers.isEmpty {
                                    EmptyStateView(isImporting: $isImporting).transition(.opacity.combined(with: .scale(scale: 0.95)))
                                } else {
                                    ForEach(filteredWallpapers) { wallpaper in
                                        WallpaperCard(wallpaper: wallpaper)
                                            .onTapGesture {
                                                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                                    self.selectedWallpaper = wallpaper
                                                    applyWallpaper(wallpaper)
                                                }
                                            }
                                            .contextMenu {
                                                Button(NSLocalizedString("show_in_finder", comment: "")) {
                                                    if let path = wallpaper.absolutePath { NSWorkspace.shared.activateFileViewerSelecting([path]) }
                                                }
                                                let type = wallpaper.type?.lowercased() ?? "video"
                                                if type == "video" || type == "scene" {
                                                    Button(action: {
                                                        if let path = wallpaper.absolutePath {
                                                            WallpaperPersistence.shared.setScreensaverConfig(wallpaperId: wallpaper.id, filePath: path, loadToMemory: loadToMemory)
                                                            showScreensaverSetAlert = true
                                                        }
                                                    }) { Label("设置为动态屏保", systemImage: "display.2") }
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
                                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor, lineWidth: selectedWallpaper?.id == wallpaper.id ? 4 : 0).animation(.easeInOut(duration: 0.2), value: selectedWallpaper?.id))
                                    }
                                }
                            }
                            .padding()
                            .animation(.easeInOut(duration: 0.3), value: selectedCategory)
                        }
                        
                        Divider()
                        
                        HStack(spacing: 16) {
                            Button(action: { isImporting = true }) { Label(NSLocalizedString("add_button", comment: ""), systemImage: "plus") }
                            Divider().frame(height: 20)
                            Button(action: toggleGlobalPause) { Image(systemName: isGlobalPaused ? "play.fill" : "pause.fill").font(.title2) }.buttonStyle(.borderless)
                            Button(action: stopCurrentMonitor) { Label(NSLocalizedString("stop_button", comment: ""), systemImage: "square.fill") }
                            Button(action: toggleIcons) { Label(areIconsHidden ? NSLocalizedString("show_icons", comment: "Show Icons") : NSLocalizedString("hide_icons", comment: "Hide Icons"), systemImage: areIconsHidden ? "eye.slash.fill" : "eye.fill") }.help(NSLocalizedString("hide_icons_help", comment: "Hide Desktop Icons"))
                            Spacer()
                            if isProcessingImport { HStack { ProgressView().controlSize(.small); Text(importProgressText).font(.caption).foregroundColor(.secondary) }.padding(.trailing) }
                            Button(action: { showSettings = true }) { Label(NSLocalizedString("settings_button", comment: ""), systemImage: "gearshape") }
                        }
                        .padding()
                        .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow))
                    }
                    .transition(.move(edge: .leading))
                }
            }
            .edgesIgnoringSafeArea(.top)
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in handleDrop(providers: providers) }
            
        } detail: {
            ZStack {
                VisualEffectView(material: .contentBackground, blendingMode: .behindWindow).ignoresSafeArea()
                
                if selectedCategory == "workshop" {
                    if let item = selectedWorkshopItem {
                        WorkshopInspector(item: item).id(item.id).transition(.move(edge: .trailing).combined(with: .opacity)).animation(.easeInOut(duration: 0.3), value: item.id)
                    } else {
                        VStack {
                            Image(systemName: "globe").font(.system(size: 60)).foregroundColor(.secondary.opacity(0.3))
                            Text("在左侧列表中浏览和下载壁纸").foregroundColor(.secondary).padding(.top)
                        }
                    }
                } else {
                    if let wallpaper = selectedWallpaper, let monitor = selectedMonitor {
                        WallpaperInspector(wallpaper: wallpaper, monitor: monitor).id(wallpaper.id).transition(.move(edge: .trailing).combined(with: .opacity)).animation(.easeInOut(duration: 0.3), value: wallpaper.id)
                    } else {
                        Text(NSLocalizedString("select_wallpaper_message", comment: "")).foregroundColor(.secondary).font(.title2)
                    }
                }
            }
        }
        .frame(minWidth: 1000, minHeight: 600)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("omw_steam_download_complete"))) { notification in
            if let userInfo = notification.userInfo, let path = userInfo["path"] as? URL { handleSteamDownload(path: path) }
        }
        .alert("设置成功", isPresented: $showScreensaverSetAlert) { Button("好的", role: .cancel) { } } message: { Text("该内容已设置为动态屏保。\n请在“系统设置 -> 屏幕保护程序”中选择 OpenMetalScreensaver 即可预览。") }
        .alert("导入状态", isPresented: $showImportAlert) { Button("OK", role: .cancel) { } } message: { Text(importStatusMessage) }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.folder], allowsMultipleSelection: true) { result in
            if let urls = try? result.get() { for url in urls { guard url.startAccessingSecurityScopedResource() else { continue } }; handleBatchImport(urls: urls) }
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
                            let name = newWallpaperName; showNewWallpaperSheet = false; isProcessingImport = true
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
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("omw_icons_hidden_changed"))) { _ in self.areIconsHidden = WallpaperEngine.shared.areIconsHidden }
    }
    
    private func handleSteamDownload(path: URL) {
        isProcessingImport = true
        importProgressText = "正在导入壁纸..."
        SteamService.shared.appendLog("[系统] 开始导入流程...")
        
        DispatchQueue.global(qos: .userInitiated).async {
            let fileManager = FileManager.default
            let isScene = fileManager.fileExists(atPath: path.appendingPathComponent("scene.pkg").path)
            
            if isScene {
                SteamService.shared.appendLog("[系统] 识别为场景壁纸，开始解包...")
                self.library.importSceneWallpaper(url: path) { progress in
                    DispatchQueue.main.async {
                        self.importProgressText = progress
                        SteamService.shared.updateProgress(text: progress, value: 1.0)
                    }
                } completion: { success, msg in
                    DispatchQueue.main.async {
                        self.isProcessingImport = false
                        self.importStatusMessage = success ? "导入成功！" : "导入失败: \(msg)"
                        SteamService.shared.appendLog("[系统] " + self.importStatusMessage)
                        self.showImportAlert = true
                        SteamService.shared.completeTask()
                        if success {
                            self.selectedCategory = "installed"
                            // 自动应用逻辑
                            let folderName = path.lastPathComponent
                            if let newWp = self.library.wallpapers.first(where: { $0.id.contains(folderName) || $0.absolutePath?.lastPathComponent == folderName }) {
                                self.selectedWallpaper = newWp
                                self.applyWallpaper(newWp)
                            }
                        }
                    }
                }
            } else {
                SteamService.shared.appendLog("[系统] 识别为视频/网页壁纸，移动文件中...")
                let destName = path.lastPathComponent
                let destURL = self.library.storageURL.appendingPathComponent(destName)
                
                do {
                    if fileManager.fileExists(atPath: destURL.path) { try fileManager.removeItem(at: destURL) }
                    try fileManager.copyItem(at: path, to: destURL)
                    self.library.importFromFolder(url: destURL)
                    
                    DispatchQueue.main.async {
                        self.isProcessingImport = false
                        self.importStatusMessage = "导入成功！"
                        SteamService.shared.appendLog("[系统] 导入成功")
                        self.showImportAlert = true
                        SteamService.shared.completeTask()
                        self.selectedCategory = "installed"
                        // 自动应用
                        if let newWp = self.library.wallpapers.first(where: { $0.id == destName }) {
                            self.selectedWallpaper = newWp
                            self.applyWallpaper(newWp)
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.isProcessingImport = false
                        self.importStatusMessage = "移动文件失败: \(error.localizedDescription)"
                        SteamService.shared.appendLog("[错误] \(error.localizedDescription)")
                        self.showImportAlert = true
                        SteamService.shared.completeTask()
                    }
                }
            }
        }
    }
    
    // MARK: - 常规 Helper 方法
    
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
        var videoURLs: [URL] = []
        var sceneCandidates: [URL] = []
            
        for url in urls {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
                if isDir.boolValue {
                    // Check if it's potentially a scene wallpaper
                    if FileManager.default.fileExists(atPath: url.appendingPathComponent("scene.pkg").path) ||
                        FileManager.default.fileExists(atPath: url.appendingPathComponent("project.json").path) {
                        sceneCandidates.append(url)
                    } else {
                        // Treat as video folder (old logic) or ignore
                        videoURLs.append(url)
                    }
                } else {
                    let ext = url.pathExtension.lowercased()
                    if ["mp4", "webm", "mov", "m4v"].contains(ext) {
                        self.pendingVideoURL = url; self.newWallpaperName = url.deletingPathExtension().lastPathComponent; self.showNewWallpaperSheet = true
                        return // Handle single video add via sheet
                    } else if ext == "pkg" {
                        sceneCandidates.append(url)
                    }
                }
            }
        }
            
        // Handle Scenes
        if !sceneCandidates.isEmpty {
            isProcessingImport = true
            importProgressText = "Initializing..."
                
            // Sequential processing
            func processNext(index: Int) {
                guard index < sceneCandidates.count else {
                    isProcessingImport = false
                    importStatusMessage = "Batch import complete."
                    showImportAlert = true
                    return
                }
                    
                let url = sceneCandidates[index]
                library.importSceneWallpaper(url: url) { status in
                    DispatchQueue.main.async { self.importProgressText = status }
                } completion: { success, msg in
                    print("Import \(url.lastPathComponent): \(msg)")
                    processNext(index: index + 1)
                }
            }
            processNext(index: 0)
        }
            
        // Handle Video Folders (Legacy)
        if !videoURLs.isEmpty {
            isProcessingImport = true
            importProgressText = "Importing videos..."
            DispatchQueue.global().async {
                for url in videoURLs { self.library.importFromFolder(url: url) }
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
