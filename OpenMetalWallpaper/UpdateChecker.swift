/*
 License: AGPLv3
 Author: laobamac
 File: UpdateChecker.swift
 Description: Simple GitHub Release checker using dynamic versioning.
*/

import Cocoa
import Foundation

struct GitHubRelease: Codable {
    let tagName: String
    let htmlUrl: String
    let body: String
    
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
        case body
    }
}

class UpdateChecker: NSObject {
    static let shared = UpdateChecker()
    
    private let owner = "laobamac"
    private let repo = "OpenMetalWallpaper"
    
    private var currentVersion: String {
        return AppInfo.releaseVersion
    }
    
    func checkForUpdates(userInitiated: Bool) {
        // GitHub API URL
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest") else { return }
        
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self, let data = data, error == nil else {
                if userInitiated { self?.showError(message: "检查更新失败，请检查网络连接。") }
                return
            }
            
            do {
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                self.compareVersion(release: release, userInitiated: userInitiated)
            } catch {
                if userInitiated { self.showError(message: "无法解析版本信息。") }
                print("Update Check Error: \(error)")
            }
        }
        task.resume()
    }
    
    private func compareVersion(release: GitHubRelease, userInitiated: Bool) {
        let serverVerStr = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
        let localVerStr = currentVersion
        
        if serverVerStr.compare(localVerStr, options: .numeric) == .orderedDescending {
            DispatchQueue.main.async {
                self.showUpdateAlert(release: release)
            }
        } else {
            if userInitiated {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "当前已是最新版本"
                    alert.informativeText = "当前版本: \(AppInfo.fullVersionString)\n最新发布: \(release.tagName)"
                    alert.addButton(withTitle: "好")
                    alert.runModal()
                }
            }
        }
    }
    
    private func showUpdateAlert(release: GitHubRelease) {
        let alert = NSAlert()
        alert.messageText = "发现新版本: \(release.tagName)"
        alert.informativeText = "当前版本: v\(currentVersion)\n\n更新内容:\n\(release.body)"
        alert.addButton(withTitle: "前往下载")
        alert.addButton(withTitle: "以后再说")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: release.htmlUrl) {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    private func showError(message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "更新检查错误"
            alert.informativeText = message
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }
    }
}
