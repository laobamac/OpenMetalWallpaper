/*
 License: AGPLv3
 Author: laobamac
 File: WallpaperPersistence.swift
 Description: Persist per-wallpaper settings AND active wallpaper state.
*/

import Foundation

struct WallpaperConfig: Codable {
    var volume: Float = 0.5
    var playbackRate: Float = 1.0
    var scaleMode: Int = 0
    var isLooping: Bool = true
    var videoScale: CGFloat = 1.0
    var xOffset: CGFloat = 0.0
    var yOffset: CGFloat = 0.0
}

class WallpaperPersistence {
    static let shared = WallpaperPersistence()
    
    // --- 1. 壁纸具体参数设置 ---
    
    private func makeConfigKey(monitor: String, wallpaperId: String) -> String {
        let safeMonitor = monitor.data(using: .utf8)?.base64EncodedString() ?? "unknown"
        return "omw_cfg_\(safeMonitor)_\(wallpaperId)"
    }
    
    func save(config: WallpaperConfig, monitor: String, wallpaperId: String) {
        let key = makeConfigKey(monitor: monitor, wallpaperId: wallpaperId)
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    
    func load(monitor: String, wallpaperId: String) -> WallpaperConfig? {
        let key = makeConfigKey(monitor: monitor, wallpaperId: wallpaperId)
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WallpaperConfig.self, from: data)
    }
    
    // --- 2. 记录显示器当前正在播放哪个壁纸 (新增) ---
    
    private func makeActiveKey(monitor: String) -> String {
        let safeMonitor = monitor.data(using: .utf8)?.base64EncodedString() ?? "unknown"
        return "omw_active_wp_\(safeMonitor)"
    }
    
    func saveActiveWallpaper(monitor: String, wallpaperId: String?) {
        let key = makeActiveKey(monitor: monitor)
        if let id = wallpaperId {
            UserDefaults.standard.set(id, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
    
    func loadActiveWallpaper(monitor: String) -> String? {
        let key = makeActiveKey(monitor: monitor)
        return UserDefaults.standard.string(forKey: key)
    }
}
