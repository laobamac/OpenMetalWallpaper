//
//  LaunchManager.swift
//  OpenMetalWallpaper
//
//  Created by laobamac on 2026/1/17.
//

/*
 Description: Modern Login Item Management using SMAppService
*/

import Foundation
import ServiceManagement
import Combine

class LaunchManager: ObservableObject {
    static let shared = LaunchManager()
    
    @Published var isLaunchAtLoginEnabled: Bool {
        didSet {
            updateLoginItemState()
        }
    }
    
    init() {
        // Check current status on initialization / 初始化时检查当前状态
        self.isLaunchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }
    
    private func updateLoginItemState() {
        do {
            if isLaunchAtLoginEnabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                    print("✅ 开机自启已启用 / Launch at login enabled")
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                    print("❎ 开机自启已禁用 / Launch at login disabled")
                }
            }
        } catch {
            print("🔴 更改开机自启状态失败 / Failed to change launch at login status: \(error)")
            // If failed, roll back status display / 如果失败，回滚状态显示
            DispatchQueue.main.async {
                self.isLaunchAtLoginEnabled = SMAppService.mainApp.status == .enabled
            }
        }
    }
}
