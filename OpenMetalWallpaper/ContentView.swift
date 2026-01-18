/*
 License: AGPLv3
 Author: laobamac
 File: ContentView.swift
 Description: UI with Global Pause Sync & Liquid Glass Style (macOS 16+).
 Refactored to fix compiler type-check timeout.
*/

import SwiftUI
import UniformTypeIdentifiers

// Monitor Struct
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
    
    // Animation namespace / 动画命名空间
    @Namespace private var animationSpace
    
    var filteredWallpapers: [WallpaperProject] {
        guard let category = selectedCategory else { return library.wallpapers }
        if category == "workshop" { return library.wallpapers.filter { $0.absolutePath?.path.contains("steamapps") ?? false } }
        return library.wallpapers
    }
    
    // MARK: - Subviews Extraction (Fixes Compiler Timeout)
    
    @ViewBuilder
    private var wallpaperList: some View {
        if filteredWallpapers.isEmpty {
            EmptyStateView(isImporting: $isImporting)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 240), spacing: 16)], spacing: 16) {
                    ForEach(filteredWallpapers) { wallpaper in
                        WallpaperCard(wallpaper: wallpaper)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    self.selectedWallpaper = wallpaper
                                    applyWallpaper(wallpaper)
                                }
                            }
                            .contextMenu {
                                Button(NSLocalizedString("show_in_finder", comment: "")) { if let path = wallpaper.absolutePath { NSWorkspace.shared.activateFileViewerSelecting([path]) } }
                                Divider()
                                Button(NSLocalizedString("remove_from_list", comment: "")) { WallpaperEngine.shared.stopWallpaper(id: wallpaper.id); library.removeWallpaper(id: wallpaper.id, deleteFile: false); if selectedWallpaper?.id == wallpaper.id { selectedWallpaper = nil } }
                                Button(NSLocalizedString("delete_wallpaper_file", comment: ""), role: .destructive) { WallpaperEngine.shared.stopWallpaper(id: wallpaper.id); library.removeWallpaper(id: wallpaper.id, deleteFile: true); if selectedWallpaper?.id == wallpaper.id { selectedWallpaper = nil } }
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.accentColor, lineWidth: selectedWallpaper?.id == wallpaper.id ? 4 : 0)
                                    .animation(.easeInOut(duration: 0.2), value: selectedWallpaper?.id)
                            )
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding()
                // macOS 16+ content area inset, adapted to rounded window / macOS 16+ 内容区域内缩，适应圆角窗口
                .padding(isMacOSTahoeOrLater() ? 10 : 0)
            }
        }
    }
    
    private var bottomToolbar: some View {
        HStack(spacing: 16) {
            Button(action: { isImporting = true }) { Label(NSLocalizedString("add_button", comment: ""), systemImage: "plus") }
            Divider().frame(height: 20)
            
            // Pause/Play button / 暂停/播放 按钮
            Button(action: toggleGlobalPause) {
                Image(systemName: isGlobalPaused ? "play.fill" : "pause.fill").font(.title2)
            }
            .buttonStyle(.borderless)
            .help(isGlobalPaused ? NSLocalizedString("play_help", comment: "") : NSLocalizedString("pause_help", comment: ""))
            .onReceive(NotificationCenter.default.publisher(for: .globalPauseDidChange)) { _ in
                self.isGlobalPaused = WallpaperEngine.shared.isGlobalPaused
            }
            
            Button(action: stopCurrentMonitor) { Label(NSLocalizedString("stop_current_screen", comment: ""), systemImage: "square.fill") }.buttonStyle(.bordered).tint(.red)
            Spacer()
            Button(action: { showSettings = true }) { Label(NSLocalizedString("settings_button", comment: ""), systemImage: "gearshape") }
        }
        .padding()
        // macOS 16+ uses glass material instead of default Material.bar / macOS 16+ 使用玻璃材质替代默认的 Material.bar
        .background(isMacOSTahoeOrLater() ? AnyView(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow).opacity(0.3)) : AnyView(Rectangle().fill(Material.bar)))
    }
    
    // MARK: - Main Body
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selectedCategory: $selectedCategory)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220)
                .background(isMacOSTahoeOrLater() ? Color.clear : nil)
        } content: {
            VStack(spacing: 0) {
                // Top monitor selector bar / 顶部显示器选择栏
                MonitorPickerHeader(monitors: monitors, selectedMonitor: $selectedMonitor, refreshAction: refreshMonitors)
                    .padding(.bottom, isMacOSTahoeOrLater() ? 8 : 0)
                
                // Extracted list view / 提取的列表视图
                wallpaperList
                
                Divider()
                
                // Extracted bottom toolbar / 提取的底部工具栏
                bottomToolbar
            }
            .navigationSplitViewColumnWidth(min: 400, ideal: 600)
            .liquidGlassStyle() // Core glass effect (only active on macOS 16+) / 核心玻璃效果 (只在 macOS 16+ 生效)
            .cornerRadius(isMacOSTahoeOrLater() ? 16 : 0)
            .padding(isMacOSTahoeOrLater() ? 10 : 0)
            .animation(.smooth, value: filteredWallpapers.count)
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in handleDrop(providers: providers) }
            .ignoresSafeArea(edges: .top)
        } detail: {
            if let wallpaper = selectedWallpaper, let monitor = selectedMonitor {
                WallpaperInspector(wallpaper: wallpaper, monitor: monitor)
                    .id(wallpaper.id)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                Text(NSLocalizedString("select_wallpaper_message", comment: ""))
                    .foregroundColor(.secondary)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in if let url = try? result.get().first { guard url.startAccessingSecurityScopedResource() else { return }; library.importFromFolder(url: url) } }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showNewWallpaperSheet) {
            VStack(spacing: 20) {
                Text(NSLocalizedString("new_video_wallpaper_title", comment: "")).font(.headline)
                TextField(NSLocalizedString("wallpaper_name_placeholder", comment: ""), text: $newWallpaperName).textFieldStyle(.roundedBorder).frame(width: 300)
                HStack {
                    Button(NSLocalizedString("cancel_button", comment: "")) { showNewWallpaperSheet = false; pendingVideoURL = nil }.keyboardShortcut(.cancelAction)
                    Button(NSLocalizedString("create_button", comment: "")) { if let url = pendingVideoURL { library.importVideoFile(url: url, title: newWallpaperName); showNewWallpaperSheet = false; pendingVideoURL = nil } }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                }
            }.padding().frame(width: 350, height: 150)
        }
        .onAppear { if selectedMonitor == nil { selectedMonitor = monitors.first }; syncSelection() }
        .onChange(of: selectedMonitor) { syncSelection() }
        .onReceive(NotificationCenter.default.publisher(for: .wallpaperDidChange)) { _ in syncSelection() }
    }
    
    // Logic (Keep same)
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
    private func toggleGlobalPause() { WallpaperEngine.shared.togglePause() }
    private func stopCurrentMonitor() { guard let monitor = selectedMonitor?.screen else { return }; WallpaperEngine.shared.stop(screen: monitor); self.selectedWallpaper = nil; self.isGlobalPaused = false }
}

// Subviews (unchanged) / Subviews (保持不变)
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
                        Text(NSLocalizedString("display_header", comment: "")).font(.headline)
                        Spacer()
                        Button(NSLocalizedString("restore_defaults_button", comment: "")) {
                            let controller = WallpaperEngine.shared.getController(for: monitor.screen)
                            controller.resetSettings()
                        }.font(.caption)
                    }
                    if !isWeb {
                        Picker(NSLocalizedString("mode_label", comment: ""), selection: $scaleMode) { ForEach(WallpaperScaleMode.allCases) { mode in Text(mode.label).tag(mode) } }.pickerStyle(.radioGroup).onChange(of: scaleMode) { syncToEngine() }
                        if scaleMode == .custom {
                            VStack(spacing: 12) {
                                Divider()
                                HStack { Text(NSLocalizedString("scale_label", comment: "")); Spacer(); Text(String(format: "%.2f", manualScale)).monospacedDigit().foregroundColor(.secondary) }
                                Slider(value: $manualScale, in: 0.5...5.0)
                                HStack { Text(NSLocalizedString("x_axis_label", comment: "")); Spacer(); Text("\(Int(manualOffsetX))").monospacedDigit().foregroundColor(.secondary) }
                                Slider(value: $manualOffsetX, in: -800...800)
                                HStack { Text(NSLocalizedString("y_axis_label", comment: "")); Spacer(); Text("\(Int(manualOffsetY))").monospacedDigit().foregroundColor(.secondary) }
                                Slider(value: $manualOffsetY, in: -800...800)
                                Button(NSLocalizedString("reset_custom_params_button", comment: "")) { manualScale = 1.0; manualOffsetX = 0; manualOffsetY = 0 }.font(.caption).padding(.top, 4)
                                Divider()
                            }.padding(.leading, 8).transition(.opacity)
                        }
                    } else { Text(NSLocalizedString("web_wallpaper_auto_adapt", comment: "")).font(.caption).foregroundColor(.secondary) }
                    HStack {
                        Text(NSLocalizedString("rotation_label", comment: ""))
                        Spacer()
                        Picker("", selection: $rotation) { Text("0°").tag(0); Text("90°").tag(90); Text("180°").tag(180); Text("270°").tag(270) }.pickerStyle(.menu).frame(width: 100)
                    }.onChange(of: rotation) { syncToEngine() }
                    if isWeb { HStack { Text(NSLocalizedString("background_color_web_label", comment: "")); Spacer(); ColorPicker("", selection: $backgroundColor, supportsOpacity: false).labelsHidden() }.onChange(of: backgroundColor) { syncToEngine() } }
                    Divider()
                    Text(NSLocalizedString("playback_header", comment: "")).font(.headline)
                    HStack { Text(NSLocalizedString("volume_label", comment: "")); Spacer(); Text("\(Int(volume * 100))%") }
                    Slider(value: $volume, in: 0...1)
                    HStack { Text(NSLocalizedString("rate_label", comment: "")); Spacer(); Text(String(format: "%.1fx", playbackRate)) }
                    Slider(value: $playbackRate, in: 0.1...2.0, step: 0.1)
                    Toggle(NSLocalizedString("loop_playback", comment: ""), isOn: $isLoopEnabled)
                }
                Spacer()
            }.padding()
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear(perform: loadFromEngine)
        .onChange(of: volume) { syncToEngine() }
        .onChange(of: playbackRate) { syncToEngine() }
        .onChange(of: isLoopEnabled) { syncToEngine() }
        .onChange(of: manualScale) { syncToEngine() }
        .onChange(of: manualOffsetX) { syncToEngine() }
        .onChange(of: manualOffsetY) { syncToEngine() }
        .onChange(of: rotation) { syncToEngine() }
        .onChange(of: backgroundColor) { syncToEngine() }
        .onChange(of: monitor) { loadFromEngine() }
        .onReceive(NotificationCenter.default.publisher(for: .wallpaperDidChange)) { _ in loadFromEngine() }
    }
    
    private func loadFromEngine() {
        let controller = WallpaperEngine.shared.getController(for: monitor.screen)
        if controller.currentWallpaperID == wallpaper.id {
            self.volume = controller.volume; self.playbackRate = controller.playbackRate; self.isLoopEnabled = controller.isLooping
            self.scaleMode = controller.scaleMode; self.manualScale = controller.videoScale == 0 ? 1.0 : controller.videoScale
            self.manualOffsetX = controller.xOffset; self.manualOffsetY = controller.yOffset; self.backgroundColor = Color(nsColor: controller.backgroundColor)
            self.rotation = controller.rotation
        }
    }
    
    private func syncToEngine() {
        let controller = WallpaperEngine.shared.getController(for: monitor.screen)
        guard controller.currentWallpaperID == wallpaper.id else { return }
        controller.volume = self.volume; controller.playbackRate = self.playbackRate
        if controller.isLooping != self.isLoopEnabled { controller.isLooping = self.isLoopEnabled }
        controller.scaleMode = self.scaleMode
        if self.scaleMode == .custom { controller.videoScale = self.manualScale; controller.xOffset = self.manualOffsetX; controller.yOffset = self.manualOffsetY }
        controller.backgroundColor = NSColor(self.backgroundColor); controller.rotation = self.rotation
    }
}

struct SidebarView: View {
    @Binding var selectedCategory: String?
    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedCategory) { Section(header: Text(NSLocalizedString("library_header", comment: ""))) { Label(NSLocalizedString("installed_label", comment: ""), systemImage: "externaldrive.fill").tag("installed") }; Section(header: Text(NSLocalizedString("discover_header", comment: ""))) { Label(NSLocalizedString("workshop_label", comment: ""), systemImage: "globe").tag("workshop") } }.listStyle(.sidebar)
            Spacer()
            VStack(alignment: .leading, spacing: 10) { Divider(); Link(destination: URL(string: "https://github.com/laobamac/OpenMetalWallpaper")!) { HStack(alignment: .center, spacing: 12) { if let logoImage = NSImage(named: "AppLogo") { Image(nsImage: logoImage).resizable().aspectRatio(contentMode: .fit).frame(width: 40, height: 40) } else { Image(nsImage: NSApp.applicationIconImage).resizable().aspectRatio(contentMode: .fit).frame(width: 40, height: 40) }; VStack(alignment: .leading, spacing: 0) { Text("OpenMetalWallpaper").font(.system(size: 13, weight: .bold)).foregroundColor(.primary).lineLimit(1).minimumScaleFactor(0.8); Text("By laobamac").font(.caption).foregroundColor(.secondary) } } }.buttonStyle(.plain).padding(.top, 4); HStack { Text("License: AGPLv3").font(.system(size: 10, weight: .bold, design: .monospaced)).padding(4).background(Color.gray.opacity(0.2)).cornerRadius(4); Spacer() } }.padding().background(Color(nsColor: .controlBackgroundColor))
        }
    }
}

struct MonitorPickerHeader: View {
    let monitors: [Monitor]; @Binding var selectedMonitor: Monitor?; var refreshAction: () -> Void
    var body: some View { HStack { Image(systemName: "display"); Text(NSLocalizedString("current_display", comment: "")).foregroundColor(.secondary); Picker("", selection: $selectedMonitor) { ForEach(monitors) { monitor in Text(monitor.name).tag(monitor as Monitor?) } }.pickerStyle(.menu).frame(width: 200); Spacer(); Button(action: refreshAction) { Image(systemName: "arrow.triangle.2.circlepath") } }.padding(.horizontal).padding(.vertical, 8).background(Material.bar) }
}

struct EmptyStateView: View {
    @Binding var isImporting: Bool
    var body: some View { VStack(spacing: 20) { Image(systemName: "photo.on.rectangle.angled").font(.system(size: 60)).foregroundColor(.secondary); Text(NSLocalizedString("no_wallpapers_found", comment: "")).font(.title); Text(NSLocalizedString("drag_drop_hint", comment: "")).font(.caption).foregroundColor(.secondary); Button(NSLocalizedString("import_now_button", comment: "")) { isImporting = true }.buttonStyle(.borderedProminent).controlSize(.large) }.frame(maxWidth: .infinity, maxHeight: .infinity) }
}
