/*
 License: AGPLv3
 Author: laobamac
 File: ContentView.swift
 Description: UI with Delete-Stop logic.
*/

import SwiftUI
import UniformTypeIdentifiers

struct Monitor: Identifiable, Hashable {
    let id: String
    let name: String
    let screen: NSScreen
    static func getAll() -> [Monitor] {
        return NSScreen.screens.map { Monitor(id: $0.localizedName, name: $0.localizedName, screen: $0) }
    }
}

struct ContentView: View {
    @EnvironmentObject var library: WallpaperLibrary
    
    @State private var selectedCategory: String? = "installed"
    @State private var selectedWallpaper: WallpaperProject?
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    @State private var monitors: [Monitor] = Monitor.getAll()
    @State private var selectedMonitor: Monitor? = Monitor.getAll().first
    
    @State private var showSettings = false
    @State private var isImporting = false
    @State private var isGlobalPaused: Bool = false
    
    @State private var showNewWallpaperSheet = false
    @State private var pendingVideoURL: URL?
    @State private var newWallpaperName: String = ""
    
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
        } content: {
            VStack(spacing: 0) {
                MonitorPickerHeader(monitors: monitors, selectedMonitor: $selectedMonitor, refreshAction: refreshMonitors)
                
                if filteredWallpapers.isEmpty {
                    EmptyStateView(isImporting: $isImporting)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 240), spacing: 16)], spacing: 16) {
                            ForEach(filteredWallpapers) { wallpaper in
                                WallpaperCard(wallpaper: wallpaper)
                                    .onTapGesture {
                                        self.selectedWallpaper = wallpaper
                                        applyWallpaper(wallpaper)
                                    }
                                    .contextMenu {
                                        Button("在 Finder 中显示") {
                                            if let path = wallpaper.absolutePath {
                                                NSWorkspace.shared.activateFileViewerSelecting([path])
                                            }
                                        }
                                        Divider()
                                        Button("从列表移除") {
                                            WallpaperEngine.shared.stopWallpaper(id: wallpaper.id)
                                            library.removeWallpaper(id: wallpaper.id, deleteFile: false)
                                            if selectedWallpaper?.id == wallpaper.id { selectedWallpaper = nil }
                                        }
                                        Button("删除壁纸文件 (物理删除)", role: .destructive) {
                                            WallpaperEngine.shared.stopWallpaper(id: wallpaper.id)
                                            library.removeWallpaper(id: wallpaper.id, deleteFile: true)
                                            if selectedWallpaper?.id == wallpaper.id { selectedWallpaper = nil }
                                        }
                                    }
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.accentColor, lineWidth: selectedWallpaper?.id == wallpaper.id ? 4 : 0)
                                    )
                            }
                        }
                        .padding()
                    }
                }
                
                Divider()
                HStack(spacing: 16) {
                    Button(action: { isImporting = true }) { Label("添加", systemImage: "plus") }
                    Divider().frame(height: 20)
                    
                    Button(action: toggleGlobalPause) {
                        Image(systemName: isGlobalPaused ? "play.fill" : "pause.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.borderless)
                    .help(isGlobalPaused ? "继续播放" : "暂停播放")
                    
                    Button(action: stopCurrentMonitor) {
                        Label("停止当前屏幕", systemImage: "square.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    
                    Spacer()
                    Button(action: { showSettings = true }) { Label("设置", systemImage: "gearshape") }
                }
                .padding()
                .background(Material.bar)
            }
            .navigationSplitViewColumnWidth(min: 400, ideal: 600)
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                handleDrop(providers: providers)
            }
            
        } detail: {
            if let wallpaper = selectedWallpaper, let monitor = selectedMonitor {
                WallpaperInspector(wallpaper: wallpaper, monitor: monitor)
            } else {
                Text("选择一张壁纸以编辑属性")
                    .foregroundColor(.secondary)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            if let url = try? result.get().first {
                guard url.startAccessingSecurityScopedResource() else { return }
                library.importFromFolder(url: url)
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showNewWallpaperSheet) {
            VStack(spacing: 20) {
                Text("新建视频壁纸").font(.headline)
                TextField("壁纸名称", text: $newWallpaperName).textFieldStyle(.roundedBorder).frame(width: 300)
                HStack {
                    Button("取消") { showNewWallpaperSheet = false; pendingVideoURL = nil }.keyboardShortcut(.cancelAction)
                    Button("创建") {
                        if let url = pendingVideoURL {
                            library.importVideoFile(url: url, title: newWallpaperName)
                            showNewWallpaperSheet = false
                            pendingVideoURL = nil
                        }
                    }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                }
            }.padding().frame(width: 350, height: 150)
        }
        .onAppear {
            if selectedMonitor == nil { selectedMonitor = monitors.first }
            syncSelection()
        }
        .onChange(of: selectedMonitor) { syncSelection() }
        .onReceive(NotificationCenter.default.publisher(for: .wallpaperDidChange)) { _ in syncSelection() }
    }
    
    // Logic (Keep same logic methods)
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (urlData, error) in
            DispatchQueue.main.async {
                if let urlData = urlData as? Data, let url = URL(dataRepresentation: urlData, relativeTo: nil) {
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
                        if isDir.boolValue {
                            library.importFromFolder(url: url)
                        } else {
                            let ext = url.pathExtension.lowercased()
                            if ["mp4", "webm", "mov", "m4v", "avi"].contains(ext) {
                                self.pendingVideoURL = url
                                self.newWallpaperName = url.deletingPathExtension().lastPathComponent
                                self.showNewWallpaperSheet = true
                            } else if ext == "html" || ext == "htm" {
                                library.importFromFolder(url: url.deletingLastPathComponent())
                            }
                        }
                    }
                }
            }
        }
        return true
    }
    
    private func syncSelection() {
        guard let monitor = selectedMonitor?.screen else { return }
        let controller = WallpaperEngine.shared.getController(for: monitor)
        if let currentId = controller.currentWallpaperID {
            if let wallpaper = library.wallpapers.first(where: { $0.id == currentId }) {
                self.selectedWallpaper = wallpaper
            }
        }
        self.isGlobalPaused = WallpaperEngine.shared.isGlobalPaused
    }
    
    private func refreshMonitors() {
        monitors = Monitor.getAll()
        if !monitors.contains(where: { $0.id == selectedMonitor?.id }) { selectedMonitor = monitors.first }
    }
    
    private func applyWallpaper(_ wallpaper: WallpaperProject) {
        guard let monitor = selectedMonitor?.screen, let path = wallpaper.absolutePath else { return }
        WallpaperEngine.shared.play(url: path, wallpaperId: wallpaper.id, screen: monitor, loadToMemory: loadToMemory)
        self.isGlobalPaused = WallpaperEngine.shared.isGlobalPaused
    }
    
    private func toggleGlobalPause() {
        WallpaperEngine.shared.togglePause()
        self.isGlobalPaused = WallpaperEngine.shared.isGlobalPaused
    }
    
    private func stopCurrentMonitor() {
        guard let monitor = selectedMonitor?.screen else { return }
        WallpaperEngine.shared.stop(screen: monitor)
        self.selectedWallpaper = nil
        self.isGlobalPaused = false
    }
}

// Subviews (SidebarView, Header, Inspector, EmptyState - Same as before)
struct SidebarView: View {
    @Binding var selectedCategory: String?
    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedCategory) {
                Section(header: Text("壁纸库")) {
                    Label("已安装", systemImage: "externaldrive.fill").tag("installed")
                }
                Section(header: Text("发现")) {
                    Label("创意工坊", systemImage: "globe").tag("workshop")
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
                            Text("OpenMetalWallpaper").font(.system(size: 13, weight: .bold)).foregroundColor(.primary).lineLimit(1).minimumScaleFactor(0.8)
                            Text("By laobamac").font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                HStack {
                    Text("License: AGPLv3").font(.system(size: 10, weight: .bold, design: .monospaced)).padding(4).background(Color.gray.opacity(0.2)).cornerRadius(4)
                    Spacer()
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }
}

struct MonitorPickerHeader: View {
    let monitors: [Monitor]
    @Binding var selectedMonitor: Monitor?
    var refreshAction: () -> Void
    var body: some View {
        HStack {
            Image(systemName: "display")
            Text("当前配置:").foregroundColor(.secondary)
            Picker("", selection: $selectedMonitor) {
                ForEach(monitors) { monitor in Text(monitor.name).tag(monitor as Monitor?) }
            }.pickerStyle(.menu).frame(width: 200)
            Spacer()
            Button(action: refreshAction) { Image(systemName: "arrow.triangle.2.circlepath") }
        }.padding(.horizontal).padding(.vertical, 8).background(Material.bar)
    }
}

struct WallpaperInspector: View {
    let wallpaper: WallpaperProject
    let monitor: Monitor
    @State private var volume: Float = 0.5
    @State private var playbackRate: Float = 1.0
    @State private var isLoopEnabled: Bool = true
    @State private var scaleMode: WallpaperScaleMode = .fill
    @State private var manualScale: CGFloat = 1.0
    @State private var manualOffsetX: CGFloat = 0.0
    @State private var manualOffsetY: CGFloat = 0.0
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let thumbPath = wallpaper.thumbnailPath, let nsImage = NSImage(contentsOf: thumbPath) {
                    Image(nsImage: nsImage).resizable().aspectRatio(contentMode: .fit).cornerRadius(8).frame(maxWidth: .infinity)
                }
                VStack(alignment: .leading) {
                    Text(wallpaper.title).font(.title3).bold()
                    Text(monitor.name).font(.caption).foregroundColor(.accentColor)
                }
                Divider()
                Group {
                    Text("显示").font(.headline)
                    Picker("模式", selection: $scaleMode) {
                        ForEach(WallpaperScaleMode.allCases) { mode in Text(mode.label).tag(mode) }
                    }.pickerStyle(.radioGroup).onChange(of: scaleMode) { syncToEngine() }
                    
                    if scaleMode == .custom {
                        VStack(spacing: 12) {
                            Divider()
                            HStack { Text("缩放"); Spacer(); Text(String(format: "%.2f", manualScale)).monospacedDigit().foregroundColor(.secondary) }
                            Slider(value: $manualScale, in: 0.5...5.0)
                            HStack { Text("X 轴"); Spacer(); Text("\(Int(manualOffsetX))").monospacedDigit().foregroundColor(.secondary) }
                            Slider(value: $manualOffsetX, in: -800...800)
                            HStack { Text("Y 轴"); Spacer(); Text("\(Int(manualOffsetY))").monospacedDigit().foregroundColor(.secondary) }
                            Slider(value: $manualOffsetY, in: -800...800)
                            Button("重置自定义参数") { manualScale = 1.0; manualOffsetX = 0; manualOffsetY = 0 }.font(.caption).padding(.top, 4)
                            Divider()
                        }.padding(.leading, 8).transition(.opacity)
                    }
                    Divider()
                    Text("播放").font(.headline)
                    HStack { Text("音量"); Spacer(); Text("\(Int(volume * 100))%") }
                    Slider(value: $volume, in: 0...1)
                    HStack { Text("速率"); Spacer(); Text(String(format: "%.1fx", playbackRate)) }
                    Slider(value: $playbackRate, in: 0.1...2.0, step: 0.1)
                    Toggle("循环播放", isOn: $isLoopEnabled)
                }
                Spacer()
            }.padding()
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .onChange(of: volume) { syncToEngine() }
        .onChange(of: playbackRate) { syncToEngine() }
        .onChange(of: isLoopEnabled) { syncToEngine() }
        .onChange(of: manualScale) { syncToEngine() }
        .onChange(of: manualOffsetX) { syncToEngine() }
        .onChange(of: manualOffsetY) { syncToEngine() }
        .onAppear(perform: loadFromEngine)
        .onChange(of: monitor) { loadFromEngine() }
        .onChange(of: wallpaper.id) { loadFromEngine() }
    }
    
    private func loadFromEngine() {
        let controller = WallpaperEngine.shared.getController(for: monitor.screen)
        self.volume = controller.volume
        self.playbackRate = controller.playbackRate
        self.isLoopEnabled = controller.isLooping
        self.scaleMode = controller.scaleMode
        self.manualScale = controller.videoScale == 0 ? 1.0 : controller.videoScale
        self.manualOffsetX = controller.xOffset
        self.manualOffsetY = controller.yOffset
    }
    
    private func syncToEngine() {
        let controller = WallpaperEngine.shared.getController(for: monitor.screen)
        controller.volume = self.volume
        controller.playbackRate = self.playbackRate
        if controller.isLooping != self.isLoopEnabled {
            controller.isLooping = self.isLoopEnabled
            if let url = controller.currentURL, let wId = controller.currentWallpaperID {
                controller.play(url: url, wallpaperId: wId, loadToMemory: controller.isMemoryMode)
            }
        }
        controller.scaleMode = self.scaleMode
        if self.scaleMode == .custom {
            controller.videoScale = self.manualScale
            controller.xOffset = self.manualOffsetX
            controller.yOffset = self.manualOffsetY
        }
    }
}

struct EmptyStateView: View {
    @Binding var isImporting: Bool
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled").font(.system(size: 60)).foregroundColor(.secondary)
            Text("没有找到壁纸").font(.title)
            Text("拖放视频文件或文件夹到此处").font(.caption).foregroundColor(.secondary)
            Button("立即导入") { isImporting = true }.buttonStyle(.borderedProminent).controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
