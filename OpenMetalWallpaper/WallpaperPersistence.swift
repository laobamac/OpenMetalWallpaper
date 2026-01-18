/*
 License: AGPLv3
 Author: laobamac
 File: WallpaperPersistence.swift
 Description: Persistence with Clear Data Feature.
*/

import Cocoa

struct WallpaperConfig: Codable {
    var volume: Float = 0.5
    var playbackRate: Float = 1.0
    var scaleMode: Int = 0
    var isLooping: Bool = true
    var videoScale: CGFloat = 1.0
    var xOffset: CGFloat = 0.0
    var yOffset: CGFloat = 0.0
    var backgroundColor: String? = "0,0,0"
    var rotation: Int = 0
}

class WallpaperPersistence {
    static let shared = WallpaperPersistence()
    
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
    
    func deleteAllUserData() {
        let defaults = UserDefaults.standard
        let dictionary = defaults.dictionaryRepresentation()
        
        dictionary.keys.forEach { key in
            // Only clear wallpaper configurations (omw_cfg_) and active wallpaper records (omw_active_wp_) / 只清除壁纸配置 (omw_cfg_) 和活动壁纸记录 (omw_active_wp_)
            // Keep bookmarks (omw_folder_bookmarks) and global settings (omw_loadToMemory etc.) / 保留书签 (omw_folder_bookmarks) 和全局设置 (omw_loadToMemory 等)
            if key.hasPrefix("omw_cfg_") || key.hasPrefix("omw_active_wp_") {
                defaults.removeObject(forKey: key)
            }
        }
        defaults.synchronize()
        print("All wallpaper configurations cleared.")
    }
}
