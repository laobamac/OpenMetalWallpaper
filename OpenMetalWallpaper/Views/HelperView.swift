//
//  HelperView.swift
//  OpenMetalWallpaper
//
//  Created by laobamac on 2026/1/17.
//

import SwiftUI

// MARK: - Models
struct Monitor: Identifiable, Hashable {
    let id: String; let name: String; let screen: NSScreen
    static func getAll() -> [Monitor] { return NSScreen.screens.map { Monitor(id: $0.localizedName, name: $0.localizedName, screen: $0) } }
}

// MARK: - Monitor Picker
struct MonitorPickerHeader: View {
    let monitors: [Monitor]
    @Binding var selectedMonitor: Monitor?
    var refreshAction: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "display")
            Text(NSLocalizedString("current_display", comment: "Display")).foregroundColor(.secondary)
            Picker("", selection: $selectedMonitor) {
                ForEach(monitors) { monitor in Text(monitor.name).tag(monitor as Monitor?) }
            }
            .pickerStyle(.menu)
            .frame(width: 200)
            
            Spacer()
            
            Button(action: refreshAction) {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.plain)
            .help("刷新显示器列表")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        // Glass effect for header
        .background(VisualEffectView(material: .headerView, blendingMode: .withinWindow))
        .cornerRadius(8)
    }
}

// MARK: - Empty State
struct EmptyStateView: View {
    @Binding var isImporting: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.5))
            Text(NSLocalizedString("no_wallpapers_found", comment: "No wallpapers"))
                .font(.title2)
                .fontWeight(.medium)
            Text(NSLocalizedString("drag_drop_hint", comment: "Drag and drop folder"))
                .font(.caption)
                .foregroundColor(.secondary)
            Button(NSLocalizedString("import_now_button", comment: "Import")) {
                isImporting = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
}

// MARK: - Localization & Text Cleaning
struct PropertyLocalizer {
    static func localize(_ key: String) -> String {
        // Clean up HTML tags like <br/>, <Br />, etc.
        let cleaned = key.replacingOccurrences(of: "<[^>]+>", with: " | ", options: .regularExpression)
                         .replacingOccurrences(of: "&lt;[^&]+&gt;", with: " | ", options: .regularExpression)
        
        // Map known keys
        let map: [String: String] = [
            "ui_browse_properties_scheme_color": "主题颜色",
            "ui_browse_properties_sound_sensitivity": "音频灵敏度",
            "ui_browse_properties_volume": "音量",
            "ui_browse_properties_alignment": "对齐方式",
            "ui_browse_properties_position": "位置",
            "schemecolor": "主题颜色",
            "sound_sensitivity": "音频灵敏度",
            "background": "背景",
            "rate": "播放速率",
            "Color": "颜色"
        ]
        
        if let val = map[cleaned.lowercased().trimmingCharacters(in: .whitespaces)] { return val }
        
        // 3. Handle Multilingual Strings (e.g. "Chinese | English")
        // Try to verify if it contains Chinese characters
        let parts = cleaned.components(separatedBy: "|")
        if parts.count > 1 {
            // Simple heuristic: return the part with Chinese, or the first part
            for part in parts {
                if part.range(of: "\\p{Han}", options: .regularExpression) != nil {
                    return part.trimmingCharacters(in: .whitespaces)
                }
            }
            return parts[0].trimmingCharacters(in: .whitespaces)
        }
        
        // 4. Default Formatting
        let final = cleaned.replacingOccurrences(of: "_", with: " ")
        return final.capitalized
    }
}
