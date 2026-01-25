//
//  WallpaperPersistence.swift
//  OpenMetalWallpaper
//
//  Created by laobamac on 2026/1/17.
//

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
    
    var brightness: Float = 0.0
    var contrast: Float = 1.0
    var saturation: Float = 1.0
    
    var isInteractive: Bool = false
}

class WallpaperPersistence {
    static let shared = WallpaperPersistence()
    
    // 屏保配置文件路径: ~/Library/Application Support/OpenMetalWallpaper/screensaver.json
    private var sharedConfigURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("OpenMetalWallpaper")
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder.appendingPathComponent("screensaver.json")
    }
    
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
    
    func saveActiveWallpaper(monitor: String, wallpaperId: String?, filePath: URL? = nil) {
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
    
    // MARK: - Manual Screensaver Set
    func setScreensaverConfig(wallpaperId: String, filePath: URL, loadToMemory: Bool) {
        let configData: [String: String] = [
            "wallpaperId": wallpaperId,
            "filePath": filePath.path,
            "loadToMemory": loadToMemory ? "true" : "false" // 写入内存设置
        ]
        
        do {
            let fileURL = sharedConfigURL
            let data = try JSONEncoder().encode(configData)
            try data.write(to: fileURL)
            print("Manual screensaver set: \(filePath.lastPathComponent), Memory: \(loadToMemory)")
        } catch {
            print("Failed to set screensaver: \(error)")
        }
    }
    
    func deleteAllUserData() {
        let defaults = UserDefaults.standard
        let dictionary = defaults.dictionaryRepresentation()
        
        dictionary.keys.forEach { key in
            if key.hasPrefix("omw_cfg_") || key.hasPrefix("omw_active_wp_") {
                defaults.removeObject(forKey: key)
            }
        }
        defaults.synchronize()
        print("All wallpaper configurations cleared.")
    }
}
