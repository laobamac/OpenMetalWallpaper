/*
 License: AGPLv3
 Author: laobamac
 File: AppInfo.swift
 Description: Centralized access to Bundle version info.
*/

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
