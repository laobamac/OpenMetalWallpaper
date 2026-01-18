/*
 License: AGPLv3
 Author: laobamac
 File: UpdateChecker.swift
 Description: Simple GitHub Release checker using dynamic versioning.
*/

import Cocoa
import Foundation

struct GitHubRelease: Sendable {
    let tagName: String
    let htmlUrl: String
    let body: String
    
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
        case body
    }
}

extension GitHubRelease: Codable {
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.tagName = try container.decode(String.self, forKey: .tagName)
        self.htmlUrl = try container.decode(String.self, forKey: .htmlUrl)
        self.body = try container.decode(String.self, forKey: .body)
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tagName, forKey: .tagName)
        try container.encode(htmlUrl, forKey: .htmlUrl)
        try container.encode(body, forKey: .body)
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
                if userInitiated { self?.showError(message: NSLocalizedString("update_check_failed", comment: "")) }
                return
            }
            
            do {
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                self.compareVersion(release: release, userInitiated: userInitiated)
            } catch {
                if userInitiated { self.showError(message: NSLocalizedString("parse_version_failed", comment: "")) }
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
                    alert.messageText = NSLocalizedString("current_latest_version", comment: "")
                    alert.informativeText = String(format: NSLocalizedString("current_version_latest", comment: ""), AppInfo.fullVersionString, release.tagName)
                    alert.addButton(withTitle: NSLocalizedString("ok_button", comment: ""))
                    alert.runModal()
                }
            }
        }
    }
    
    private func showUpdateAlert(release: GitHubRelease) {
        let alert = NSAlert()
        alert.messageText = String(format: NSLocalizedString("new_version_found", comment: ""), release.tagName)
        alert.informativeText = String(format: NSLocalizedString("current_version_update", comment: ""), currentVersion, release.body)
        alert.addButton(withTitle: NSLocalizedString("download_button", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("later_button", comment: ""))
        
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
            alert.messageText = NSLocalizedString("update_check_error", comment: "")
            alert.informativeText = message
            alert.addButton(withTitle: NSLocalizedString("confirm_button", comment: ""))
            alert.runModal()
        }
    }
}
