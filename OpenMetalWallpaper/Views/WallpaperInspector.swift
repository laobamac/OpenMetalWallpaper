//
//  WallpaperInspector.swift
//  OpenMetalWallpaper
//
//  Created by laobamac on 2026/1/17.
//

import SwiftUI

struct WallpaperInspector: View {
    let wallpaper: WallpaperProject
    let monitor: Monitor
    
    // Engine State
    @State private var volume: Float = 0.5
    @State private var playbackRate: Float = 1.0
    @State private var isLoopEnabled: Bool = true
    
    // Visual State
    @State private var scaleMode: WallpaperScaleMode = .fill
    @State private var manualScale: CGFloat = 1.0
    @State private var manualOffsetX: CGFloat = 0.0
    @State private var manualOffsetY: CGFloat = 0.0
    @State private var rotation: Int = 0
    @State private var brightness: Float = 0.0
    @State private var contrast: Float = 1.0
    @State private var saturation: Float = 1.0
    
    // Dynamic Properties
    @State private var webProps: [String: Any] = [:]
    
    // Preview Zoom State
    @State private var showPreviewZoom: Bool = false
    
    // Interaction Logic State
    @State private var isInteractive: Bool = false
    @State private var showIconHiddenAlert: Bool = false
    
    // [New] Permission Alert
    @State private var showPermissionAlert: Bool = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                
                // Header Info with Zoomable Image
                HStack(alignment: .top, spacing: 16) {
                    if let thumbPath = wallpaper.thumbnailPath, let nsImage = NSImage(contentsOf: thumbPath) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 100, height: 60)
                            .cornerRadius(6)
                            .clipped()
                            .onTapGesture {
                                showPreviewZoom = true // Trigger zoom
                            }
                            .help("点击放大预览")
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 100, height: 60)
                            .cornerRadius(6)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(wallpaper.title).font(.title2).bold()
                        Text(monitor.name).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: restoreDefaults) {
                        VStack(spacing: 2) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("重置").font(.caption2)
                        }
                    }
                    .buttonStyle(.borderless)
                    .help("恢复默认设置")
                }
                .padding(.bottom, 8)
                
                Divider()
                
                // 1.5 Interactive Toggle (Web/Scene Only)
                if wallpaper.type?.lowercased() == "web" || wallpaper.type?.lowercased() == "scene" {
                    GroupBox {
                        // 使用 Binding 的自定义 set 逻辑来拦截点击
                        Toggle("允许鼠标互动 (Allow Interaction)", isOn: Binding(
                            get: { isInteractive },
                            set: { newValue in
                                if newValue {
                                    // 用户想要开启互动
                                    if WallpaperEngine.shared.areIconsHidden {
                                        // 图标已经隐藏，直接开启
                                        isInteractive = true
                                        syncToEngine()
                                    } else {
                                        // 图标未隐藏，弹出提示，暂不开启
                                        showIconHiddenAlert = true
                                    }
                                } else {
                                    // 用户关闭互动，直接关闭
                                    isInteractive = false
                                    syncToEngine()
                                }
                            }
                        ))
                        .toggleStyle(.switch)
                    }
                }
                
                // Web Properties
                if let properties = wallpaper.general?.properties, !properties.isEmpty {
                    Text("壁纸设置 (Properties)").font(.headline)
                    LazyVStack(alignment: .leading, spacing: 16) {
                        let sortedKeys = properties.keys.sorted { (properties[$0]?.order ?? 0) < (properties[$1]?.order ?? 0) }
                        ForEach(sortedKeys, id: \.self) { key in
                            if let config = properties[key] {
                                PropertyControl(key: key, config: config, value: Binding(
                                    get: { webProps[key] ?? config.value?.rawValue ?? "" },
                                    set: { newVal in webProps[key] = newVal; updateWebProperty(key: key, value: newVal) }
                                ))
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                    Divider()
                }
                
                // Post Processing
                GroupBox(label: Text("画面调节 (Post Processing)").bold()) {
                    VStack(spacing: 12) {
                        LabeledSlider(label: "亮度", value: $brightness, range: -0.5...0.5, format: "%.2f")
                        LabeledSlider(label: "对比度", value: $contrast, range: 0.5...2.0, format: "%.2f")
                        LabeledSlider(label: "饱和度", value: $saturation, range: 0.0...2.0, format: "%.2f")
                    }.padding(8)
                }
                .onChange(of: brightness) { syncToEngine() }
                .onChange(of: contrast) { syncToEngine() }
                .onChange(of: saturation) { syncToEngine() }
                
                // Transform
                GroupBox(label: Text("位置与变换 (Transform)").bold()) {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("模式", selection: $scaleMode) {
                            ForEach(WallpaperScaleMode.allCases) { mode in Text(mode.label).tag(mode) }
                        }.pickerStyle(.segmented)
                        
                        if scaleMode == .custom {
                            LabeledSliderCGFloat(label: "缩放", value: $manualScale, range: 0.1...5.0, format: "%.2f")
                            LabeledSliderCGFloat(label: "X 偏移", value: $manualOffsetX, range: -1000...1000, format: "%.0f")
                            LabeledSliderCGFloat(label: "Y 偏移", value: $manualOffsetY, range: -1000...1000, format: "%.0f")
                        }
                        
                        HStack {
                            Text("旋转")
                            Spacer()
                            Picker("", selection: $rotation) {
                                Text("0°").tag(0); Text("90°").tag(90); Text("180°").tag(180); Text("270°").tag(270)
                            }.pickerStyle(.segmented).frame(width: 200)
                        }
                    }.padding(8)
                }
                .onChange(of: scaleMode) { syncToEngine() }
                .onChange(of: rotation) { syncToEngine() }
                .onChange(of: manualScale) { syncToEngine() }
                .onChange(of: manualOffsetX) { syncToEngine() }
                .onChange(of: manualOffsetY) { syncToEngine() }
                
                // 5. Playback
                GroupBox(label: Text("播放控制 (Playback)").bold()) {
                    VStack(spacing: 12) {
                        LabeledSlider(label: "音量", value: $volume, range: 0...1, format: "%.0f%%", multiplier: 100)
                        LabeledSlider(label: "速率", value: $playbackRate, range: 0.1...2.0, format: "%.1fx")
                        Toggle("循环播放", isOn: $isLoopEnabled)
                    }.padding(8)
                }
                .onChange(of: volume) { syncToEngine() }
                .onChange(of: playbackRate) { syncToEngine() }
                .onChange(of: isLoopEnabled) { syncToEngine() }
                
                Spacer().frame(height: 50)
            }
            .padding(20)
        }
        .onAppear(perform: loadFromEngine)
        .onChange(of: monitor) { loadFromEngine() }
        .onReceive(NotificationCenter.default.publisher(for: .wallpaperDidChange)) { _ in loadFromEngine() }
        
        // Icon Hidden Alert (Updated Logic with 3 Options)
        .alert("需要隐藏桌面图标", isPresented: $showIconHiddenAlert) {
            Button("隐藏并开启") {
                // 1. 隐藏图标 (全局)
                if !WallpaperEngine.shared.areIconsHidden {
                    WallpaperEngine.shared.toggleHideIcons()
                    // 强制刷新 ContentView 的按钮状态
                    NotificationCenter.default.post(name: Notification.Name("omw_icons_hidden_changed"), object: nil)
                }
                // 2. 开启互动 (当前壁纸)
                isInteractive = true
                syncToEngine()
            }
            
            Button("不隐藏并开启 (需辅助功能权限)") {
                // 仅开启互动，保持图标显示
                // 检查辅助功能权限
                if AccessibilityUtils.isTrusted() {
                    isInteractive = true
                    syncToEngine()
                } else {
                    // 没有权限，弹出提示
                    showPermissionAlert = true
                }
            }
            
            Button("取消", role: .cancel) {
                // 取消操作，isInteractive 保持为 false
            }
        } message: {
            Text("为了最佳体验，建议隐藏桌面图标以防止点击被Finder拦截。\n如果不隐藏图标，App 需要【辅助功能权限】来穿透 Finder 捕获鼠标事件。")
        }
        
        // [New] Permission Alert
        .alert("需要辅助功能权限", isPresented: $showPermissionAlert) {
            Button("去设置") {
                AccessibilityUtils.promptForPermissions()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("由于 Finder 图标层级较高，您必须在“系统设置 -> 隐私与安全性 -> 辅助功能”中授予 OpenMetalWallpaper 权限，才能在不隐藏图标的情况下控制壁纸。")
        }
        
        // Full Screen Image Overlay
        .overlay {
            if showPreviewZoom, let thumbPath = wallpaper.thumbnailPath, let nsImage = NSImage(contentsOf: thumbPath) {
                ZStack {
                    VisualEffectView(material: .fullScreenUI, blendingMode: .withinWindow)
                        .ignoresSafeArea()
                        .onTapGesture { withAnimation { showPreviewZoom = false } }
                    
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 800, maxHeight: 800)
                        .cornerRadius(12)
                        .shadow(radius: 20)
                        .onTapGesture { withAnimation { showPreviewZoom = false } }
                    
                    VStack {
                        HStack {
                            Spacer()
                            Button(action: { withAnimation { showPreviewZoom = false } }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                            .padding(20)
                        }
                        Spacer()
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: showPreviewZoom)
    }
    
    // MARK: - Logic Helpers
    private func loadFromEngine() {
        let controller = WallpaperEngine.shared.getController(for: monitor.screen)
        if controller.currentWallpaperID == wallpaper.id {
            self.volume = controller.volume; self.playbackRate = controller.playbackRate; self.isLoopEnabled = controller.isLooping
            self.scaleMode = controller.scaleMode; self.manualScale = controller.videoScale == 0 ? 1.0 : controller.videoScale
            self.manualOffsetX = controller.xOffset; self.manualOffsetY = controller.yOffset
            self.rotation = controller.rotation
            self.brightness = controller.brightness; self.contrast = controller.contrast; self.saturation = controller.saturation
            
            // Load Interaction State
            self.isInteractive = controller.isInteractive
            
            self.webProps = controller.webProperties
            if self.webProps.isEmpty, let configs = wallpaper.general?.properties {
                for (k, v) in configs { if let val = v.value { self.webProps[k] = val.rawValue } }
            }
        }
    }
    
    private func syncToEngine() {
        let controller = WallpaperEngine.shared.getController(for: monitor.screen)
        guard controller.currentWallpaperID == wallpaper.id else { return }
        controller.volume = volume; controller.playbackRate = playbackRate
        controller.isLooping = isLoopEnabled
        controller.scaleMode = scaleMode
        if scaleMode == .custom { controller.videoScale = manualScale; controller.xOffset = manualOffsetX; controller.yOffset = manualOffsetY }
        controller.rotation = rotation
        controller.setPostProcessing(brightness: brightness, contrast: contrast, saturation: saturation)
        
        // Sync Interaction State
        controller.isInteractive = isInteractive
        // Important: Update window pass-through state immediately
        controller.updateWindowInteraction()
    }
    
    private func updateWebProperty(key: String, value: Any) {
        let controller = WallpaperEngine.shared.getController(for: monitor.screen)
        guard controller.currentWallpaperID == wallpaper.id else { return }
        controller.updateWebProperty(key: key, value: value)
    }
    
    private func restoreDefaults() {
        let controller = WallpaperEngine.shared.getController(for: monitor.screen)
        controller.resetSettings()
        if let properties = wallpaper.general?.properties {
            for (key, config) in properties {
                if let defVal = config.value {
                    let raw = defVal.rawValue
                    webProps[key] = raw
                    controller.updateWebProperty(key: key, value: raw)
                }
            }
        }
        loadFromEngine()
    }
}

// MARK: - Components
struct LabeledSlider: View {
    let label: String
    @Binding var value: Float
    var range: ClosedRange<Float>
    var format: String
    var multiplier: Float = 1.0
    
    var body: some View {
        HStack {
            Text(label).frame(width: 60, alignment: .leading)
            Slider(value: $value, in: range)
            Text(String(format: format, value * multiplier)).monospacedDigit().frame(width: 50, alignment: .trailing).foregroundColor(.secondary)
        }
    }
}

struct LabeledSliderCGFloat: View {
    let label: String
    @Binding var value: CGFloat
    var range: ClosedRange<CGFloat>
    var format: String
    
    var body: some View {
        HStack {
            Text(label).frame(width: 60, alignment: .leading)
            Slider(value: $value, in: range)
            Text(String(format: format, Double(value))).monospacedDigit().frame(width: 50, alignment: .trailing).foregroundColor(.secondary)
        }
    }
}

struct PropertyControl: View {
    let key: String
    let config: WallpaperPropertyConfig
    @Binding var value: Any
    
    var label: String { PropertyLocalizer.localize(config.text ?? key) }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch config.type {
            case "slider":
                let min = config.min ?? 0; let max = config.max ?? 100
                let doubleVal = Binding<Double>(get: { (value as? Double) ?? Double((value as? Int) ?? 0) }, set: { value = $0 })
                HStack {
                    Text(label).font(.subheadline)
                    Spacer()
                    Text("\(Int(doubleVal.wrappedValue))").monospacedDigit().bold()
                }
                Slider(value: doubleVal, in: min...max)
            case "bool":
                let boolVal = Binding<Bool>(get: { (value as? Bool) ?? false }, set: { value = $0 })
                Toggle(label, isOn: boolVal).toggleStyle(.switch)
            case "color":
                let colorVal = Binding<Color>(get: { parseColor(value as? String ?? "1 1 1") }, set: { value = colorToString($0) })
                HStack { Text(label); Spacer(); ColorPicker("", selection: colorVal) }
            case "combo":
                if let options = config.options {
                    HStack {
                        Text(label)
                        Spacer()
                        let hashableBinding = Binding<AnyHashable>(
                            get: {
                                if let s = value as? String { return AnyHashable(s) }
                                if let d = value as? Double { return AnyHashable(d) }
                                if let i = value as? Int { return AnyHashable(i) }
                                return AnyHashable(0)
                            },
                            set: { value = $0.base }
                        )
                        Picker("", selection: hashableBinding) {
                            ForEach(options, id: \.self) { opt in Text(opt.label).tag(opt.value.hashableRawValue) }
                        }.pickerStyle(.menu).frame(minWidth: 120)
                    }
                }
            case "text":
                TextField(label, text: Binding(get: { (value as? String) ?? "" }, set: { value = $0 })).textFieldStyle(.roundedBorder)
            default: EmptyView()
            }
        }
    }
    
    func parseColor(_ str: String) -> Color {
        let parts = str.split(separator: " ").compactMap { Double($0) }
        return parts.count >= 3 ? Color(red: parts[0], green: parts[1], blue: parts[2]) : .white
    }
    
    func colorToString(_ color: Color) -> String {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return "1 1 1" }
        return "\(rgb.redComponent) \(rgb.greenComponent) \(rgb.blueComponent)"
    }
}
