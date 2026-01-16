/*
 License: AGPLv3
 Author: laobamac
 File: WallpaperModel.swift
 Description: Model with persistence support (Bookmarks).
*/

import Foundation
import Combine
import SwiftUI

struct WallpaperProject: Codable, Identifiable {
    var id: String { file ?? UUID().uuidString }
    let title: String
    let file: String?
    let type: String?
    let preview: String?
    
    // 运行时属性
    var absolutePath: URL?
    var thumbnailPath: URL?
    
    // 编码白名单：只保存 JSON 里的原始字段，不保存运行时路径
    private enum CodingKeys: String, CodingKey {
        case title, file, type, preview
    }
}

class WallpaperLibrary: ObservableObject {
    @Published var wallpapers: [WallpaperProject] = []
    
    private let bookmarksKey = "omw_folder_bookmarks"
    
    init() {
        restoreBookmarks()
    }
    
    func importFromFolder(url: URL) {
        // 创建Bookmark
        do {
            let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            
            // 保存到 UserDefaults
            var bookmarks = UserDefaults.standard.dictionary(forKey: bookmarksKey) as? [String: Data] ?? [:]
            bookmarks[url.absoluteString] = bookmarkData
            UserDefaults.standard.set(bookmarks, forKey: bookmarksKey)
            
            // 解析文件
            parseFolder(url: url)
        } catch {
            print("保存书签失败: \(error)")
        }
    }
    
    // 恢复上次导入的文件夹
    private func restoreBookmarks() {
        let bookmarks = UserDefaults.standard.dictionary(forKey: bookmarksKey) as? [String: Data] ?? [:]
        
        for (_, data) in bookmarks {
            var isStale = false
            do {
                let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                
                if isStale {
                    // 书签过期
                    print("书签过期: \(url)")
                }
                
                if url.startAccessingSecurityScopedResource() {
                    parseFolder(url: url)
                    // 这里不停止访问 (stopAccessing)，因为整个 App 生命周期都需要读取
                }
            } catch {
                print("解析书签失败: \(error)")
            }
        }
    }
    
    // 删除壁纸
    func removeWallpaper(id: String, deleteFile: Bool) {
        guard let index = wallpapers.firstIndex(where: { $0.id == id }) else { return }
        let wallpaper = wallpapers[index]
        
        if deleteFile, let path = wallpaper.absolutePath {
            // 删除物理文件
            let folder = path.deletingLastPathComponent()
            try? FileManager.default.removeItem(at: folder)
        }
        
        // 从列表移除
        wallpapers.remove(at: index)
    }
    
    private func parseFolder(url: URL) {
        let fileManager = FileManager.default
        // 递归查找 project.json
        if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: nil) {
            for case let fileURL as URL in enumerator {
                if fileURL.lastPathComponent == "project.json" {
                    parseProjectJSON(url: fileURL)
                }
            }
        }
    }
    
    private func parseProjectJSON(url: URL) {
        do {
            let data = try Data(contentsOf: url)
            var project = try JSONDecoder().decode(WallpaperProject.self, from: data)
            
            let folder = url.deletingLastPathComponent()
            project.absolutePath = folder.appendingPathComponent(project.file ?? "")
            if let preview = project.preview {
                project.thumbnailPath = folder.appendingPathComponent(preview)
            }
            
            // 避免重复显示
            if !wallpapers.contains(where: { $0.absolutePath == project.absolutePath }) {
                if project.type?.lowercased() == "video" {
                    DispatchQueue.main.async {
                        self.wallpapers.append(project)
                    }
                }
            }
        } catch {
            // 忽略非标准 JSON
        }
    }
}
