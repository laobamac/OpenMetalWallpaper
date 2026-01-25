//
//  AppInfo.swift
//  OpenMetalWallpaper
//
//  Created by laobamac on 2026/1/17.
//

import Foundation

struct AppInfo {
    static var releaseVersion: String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
    
    static var buildVersion: String {
        return Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }
    
    static var fullVersionString: String {
        return "v\(releaseVersion) (\(buildVersion))"
    }
    
    static var appName: String {
        return Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "OpenMetalWallpaper"
    }
}
