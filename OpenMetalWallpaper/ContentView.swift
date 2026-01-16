/*
 License: AGPLv3
 Author: laobamac
 File: ContentView.swift
 Description: UI with Strict ID Checks (Fixes bleeding) and Reset Button.
*/

import SwiftUI
import UniformTypeIdentifiers

struct Monitor: Identifiable, Hashable {
    let id: String; let name: String; let screen: NSScreen
    static func getAll() -> [Monitor] { return NSScreen.screens.map { Monitor(id: $0.localizedName, name: $0.localizedName, screen: $0) } }
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
        if category == "workshop" { return library.wallpapers.filter { $0.absolutePath?.path.contains("steamapps") ?? false } }
        return library.wallpapers
    }
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selectedCategory: $selectedCategory).navigationSplitViewColumnWidth(min: 200, ideal: 220)
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
                                    .onTapGesture { self.selectedWallpaper = wallpaper; applyWallpaper(wallpaper) }
                                    .contextMenu {
                                        Button("在 Finder 中显示") { if let path = wallpaper.absolutePath { NSWorkspace.shared.activateFileViewerSelecting([path]) } }
                                        Divider()
                                        Button("从列表移除") { WallpaperEngine.shared.stopWallpaper(id: wallpaper.id); library.removeWallpaper(id: wallpaper.id, deleteFile: false); if selectedWallpaper?.id == wallpaper.id { selectedWallpaper = nil } }
                                        Button("删除壁纸文件 (物理删除)", role: .destructive) { WallpaperEngine.shared.stopWallpaper(id: wallpaper.id); library.removeWallpaper(id: wallpaper.id, deleteFile: true); if selectedWallpaper?.id == wallpaper.id { selectedWallpaper = nil } }
                                    }
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: selectedWallpaper?.id == wallpaper.id ? 4 : 0))
                            }
                        }.padding()
                    }
                }
                Divider()
                HStack(spacing: 16) {
                    Button(action: { isImporting = true }) { Label("添加", systemImage: "plus") }
                    Divider().frame(height: 20)
                    Button(action: toggleGlobalPause) { Image(systemName: isGlobalPaused ? "play.fill" : "pause.fill").font(.title2) }.buttonStyle(.borderless).help(isGlobalPaused ? "继续播放" : "暂停播放")
                    Button(action: stopCurrentMonitor) { Label("停止当前屏幕", systemImage: "square.fill") }.buttonStyle(.bordered).tint(.red)
                    Spacer()
                    Button(action: { showSettings = true }) { Label("设置", systemImage: "gearshape") }
                }.padding().background(Material.bar)
            }
            .navigationSplitViewColumnWidth(min: 400, ideal: 600)
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in handleDrop(providers: providers) }
        } detail: {
            if let wallpaper = selectedWallpaper, let monitor = selectedMonitor {
                WallpaperInspector(wallpaper: wallpaper, monitor: monitor)
                    .id(wallpaper.id) // 强制刷新，防止 UI 状态残留
            } else {
                Text("选择一张壁纸以编辑属性").foregroundColor(.secondary)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in if let url = try? result.get().first { guard url.startAccessingSecurityScopedResource() else { return }; library.importFromFolder(url: url) } }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showNewWallpaperSheet) {
            VStack(spacing: 20) {
                Text("新建视频壁纸").font(.headline)
                TextField("壁纸名称", text: $newWallpaperName).textFieldStyle(.roundedBorder).frame(width: 300)
                HStack {
                    Button("取消") { showNewWallpaperSheet = false; pendingVideoURL = nil }.keyboardShortcut(.cancelAction)
                    Button("创建") { if let url = pendingVideoURL { library.importVideoFile(url: url, title: newWallpaperName); showNewWallpaperSheet = false; pendingVideoURL = nil } }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                }
            }.padding().frame(width: 350, height: 150)
        }
        .onAppear { if selectedMonitor == nil { selectedMonitor = monitors.first }; syncSelection() }
        .onChange(of: selectedMonitor) { syncSelection() }
        .onReceive(NotificationCenter.default.publisher(for: .wallpaperDidChange)) { _ in syncSelection() }
    }
    
    // Logic
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (urlData, error) in
            DispatchQueue.main.async {
                if let urlData = urlData as? Data, let url = URL(dataRepresentation: urlData, relativeTo: nil) {
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
                        if isDir.boolValue { library.importFromFolder(url: url) }
                        else {
                            let ext = url.pathExtension.lowercased()
                            if ["mp4", "webm", "mov", "m4v", "avi"].contains(ext) {
                                self.pendingVideoURL = url; self.newWallpaperName = url.deletingPathExtension().lastPathComponent; self.showNewWallpaperSheet = true
                            } else if ["html", "htm"].contains(ext) { library.importFromFolder(url: url.deletingLastPathComponent()) }
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
        if let currentId = controller.currentWallpaperID { if let wallpaper = library.wallpapers.first(where: { $0.id == currentId }) { self.selectedWallpaper = wallpaper } }
        self.isGlobalPaused = WallpaperEngine.shared.isGlobalPaused
    }
    private func refreshMonitors() { monitors = Monitor.getAll(); if !monitors.contains(where: { $0.id == selectedMonitor?.id }) { selectedMonitor = monitors.first } }
    private func applyWallpaper(_ wallpaper: WallpaperProject) { guard let monitor = selectedMonitor?.screen, let path = wallpaper.absolutePath else { return }; WallpaperEngine.shared.play(url: path, wallpaperId: wallpaper.id, screen: monitor, loadToMemory: loadToMemory); self.isGlobalPaused = WallpaperEngine.shared.isGlobalPaused }
    private func toggleGlobalPause() { WallpaperEngine.shared.togglePause(); self.isGlobalPaused = WallpaperEngine.shared.isGlobalPaused }
    private func stopCurrentMonitor() { guard let monitor = selectedMonitor?.screen else { return }; WallpaperEngine.shared.stop(screen: monitor); self.selectedWallpaper = nil; self.isGlobalPaused = false }
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
    @State private var backgroundColor: Color = .black
    @State private var rotation: Int = 0
    
    var isWeb: Bool {
        guard let ext = wallpaper.file?.components(separatedBy: ".").last?.lowercased() else { return false }
        return ["html", "htm"].contains(ext)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let thumbPath = wallpaper.thumbnailPath, let nsImage = NSImage(contentsOf: thumbPath) {
                    Image(nsImage: nsImage).resizable().aspectRatio(contentMode: .fit).cornerRadius(8).frame(maxWidth: .infinity)
                }
                VStack(alignment: .leading) { Text(wallpaper.title).font(.title3).bold(); Text(monitor.name).font(.caption).foregroundColor(.accentColor) }
                Divider()
                Group {
                    HStack {
                        Text("显示").font(.headline)
                        Spacer()
                        Button("恢复默认") {
                            let controller = WallpaperEngine.shared.getController(for: monitor.screen)
                            controller.resetSettings()
                            // resetSettings 会触发 Notification，UI 会自动 reload
                        }
                        .font(.caption)
                    }
                    
                    if !isWeb {
                        Picker("模式", selection: $scaleMode) { ForEach(WallpaperScaleMode.allCases) { mode in Text(mode.label).tag(mode) } }.pickerStyle(.radioGroup).onChange(of: scaleMode) { syncToEngine() }
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
                    } else {
                        Text("Web 壁纸自动适应屏幕").font(.caption).foregroundColor(.secondary)
                    }
                    HStack {
                        Text("旋转")
                        Spacer()
                        Picker("", selection: $rotation) { Text("0°").tag(0); Text("90°").tag(90); Text("180°").tag(180); Text("270°").tag(270) }.pickerStyle(.menu).frame(width: 100)
                    }.onChange(of: rotation) { syncToEngine() }
                    
                    if isWeb { HStack { Text("背景颜色 (Web)"); Spacer(); ColorPicker("", selection: $backgroundColor, supportsOpacity: false).labelsHidden() }.onChange(of: backgroundColor) { syncToEngine() } }
                    
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
        .onAppear(perform: loadFromEngine)
        // 监听所有状态变化
        .onChange(of: volume) { syncToEngine() }
        .onChange(of: playbackRate) { syncToEngine() }
        .onChange(of: isLoopEnabled) { syncToEngine() }
        .onChange(of: manualScale) { syncToEngine() }
        .onChange(of: manualOffsetX) { syncToEngine() }
        .onChange(of: manualOffsetY) { syncToEngine() }
        .onChange(of: rotation) { syncToEngine() }
        .onChange(of: backgroundColor) { syncToEngine() }
        // 监听外部事件
        .onChange(of: monitor) { loadFromEngine() }
        .onChange(of: wallpaper.id) { loadFromEngine() }
        // 监听 Notification，确保 Reset 后或 Play 完成后 UI 刷新
        .onReceive(NotificationCenter.default.publisher(for: .wallpaperDidChange)) { _ in loadFromEngine() }
    }
    
    private func loadFromEngine() {
        let controller = WallpaperEngine.shared.getController(for: monitor.screen)
        
        // 只有当引擎正在播放当前 UI 选中的壁纸时，才读取数据
        if controller.currentWallpaperID == wallpaper.id {
            self.volume = controller.volume
            self.playbackRate = controller.playbackRate
            self.isLoopEnabled = controller.isLooping
            self.scaleMode = controller.scaleMode
            self.manualScale = controller.videoScale == 0 ? 1.0 : controller.videoScale
            self.manualOffsetX = controller.xOffset
            self.manualOffsetY = controller.yOffset
            self.backgroundColor = Color(nsColor: controller.backgroundColor)
            self.rotation = controller.rotation
        }
    }
    
    private func syncToEngine() {
        let controller = WallpaperEngine.shared.getController(for: monitor.screen)
        
        // 只有当引擎已经切换到当前壁纸时，才允许写入
        guard controller.currentWallpaperID == wallpaper.id else { return }
        
        controller.volume = self.volume
        controller.playbackRate = self.playbackRate
        if controller.isLooping != self.isLoopEnabled {
            controller.isLooping = self.isLoopEnabled
            // 这里不需要重新 play，因为 didSet 会处理
            controller.isLooping = self.isLoopEnabled
        }
        controller.scaleMode = self.scaleMode
        if self.scaleMode == .custom {
            controller.videoScale = self.manualScale
            controller.xOffset = self.manualOffsetX
            controller.yOffset = self.manualOffsetY
        }
        controller.backgroundColor = NSColor(self.backgroundColor)
        controller.rotation = self.rotation
    }
}

// Subviews
struct SidebarView: View {
    @Binding var selectedCategory: String?
    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedCategory) { Section(header: Text("壁纸库")) { Label("已安装", systemImage: "externaldrive.fill").tag("installed") }; Section(header: Text("发现")) { Label("创意工坊（未完成）", systemImage: "globe").tag("workshop") } }.listStyle(.sidebar)
            Spacer()
            VStack(alignment: .leading, spacing: 10) { Divider(); Link(destination: URL(string: "https://github.com/laobamac/OpenMetalWallpaper")!) { HStack(alignment: .center, spacing: 12) { if let logoImage = NSImage(named: "AppLogo") { Image(nsImage: logoImage).resizable().aspectRatio(contentMode: .fit).frame(width: 40, height: 40) } else { Image(nsImage: NSApp.applicationIconImage).resizable().aspectRatio(contentMode: .fit).frame(width: 40, height: 40) }; VStack(alignment: .leading, spacing: 0) { Text("OpenMetalWallpaper").font(.system(size: 13, weight: .bold)).foregroundColor(.primary).lineLimit(1).minimumScaleFactor(0.8); Text("By laobamac").font(.caption).foregroundColor(.secondary) } } }.buttonStyle(.plain).padding(.top, 4); HStack { Text("License: AGPLv3").font(.system(size: 10, weight: .bold, design: .monospaced)).padding(4).background(Color.gray.opacity(0.2)).cornerRadius(4); Spacer() } }.padding().background(Color(nsColor: .controlBackgroundColor))
        }
    }
}

struct MonitorPickerHeader: View {
    let monitors: [Monitor]; @Binding var selectedMonitor: Monitor?; var refreshAction: () -> Void
    var body: some View { HStack { Image(systemName: "display"); Text("当前配置:").foregroundColor(.secondary); Picker("", selection: $selectedMonitor) { ForEach(monitors) { monitor in Text(monitor.name).tag(monitor as Monitor?) } }.pickerStyle(.menu).frame(width: 200); Spacer(); Button(action: refreshAction) { Image(systemName: "arrow.triangle.2.circlepath") } }.padding(.horizontal).padding(.vertical, 8).background(Material.bar) }
}

struct EmptyStateView: View {
    @Binding var isImporting: Bool
    var body: some View { VStack(spacing: 20) { Image(systemName: "photo.on.rectangle.angled").font(.system(size: 60)).foregroundColor(.secondary); Text("没有找到壁纸").font(.title); Text("拖放视频文件或文件夹到此处").font(.caption).foregroundColor(.secondary); Button("立即导入") { isImporting = true }.buttonStyle(.borderedProminent).controlSize(.large) }.frame(maxWidth: .infinity, maxHeight: .infinity) }
}
