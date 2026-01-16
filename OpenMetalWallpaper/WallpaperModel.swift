/*
 License: AGPLv3
 Author: laobamac
 File: WallpaperModel.swift
 Description: Model with Main-Thread UI updates for deletion.
*/

import Foundation
import Combine
import SwiftUI
import AVFoundation

struct WallpaperProject: Codable, Identifiable {
    var id: String { file ?? UUID().uuidString }
    let title: String
    let file: String?
    let type: String?
    let preview: String?
    let description: String?
    
    // 运行时属性
    var absolutePath: URL?
    var thumbnailPath: URL?
    
    private enum CodingKeys: String, CodingKey {
        case title, file, type, preview, description
    }
}

class WallpaperLibrary: ObservableObject {
    @Published var wallpapers: [WallpaperProject] = []
    
    private let bookmarksKey = "omw_folder_bookmarks"
    private let storagePathKey = "omw_library_storage_path"
    
    var storageURL: URL {
        if let path = UserDefaults.standard.string(forKey: storagePathKey) {
            return URL(fileURLWithPath: path)
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let defaultPath = appSupport.appendingPathComponent("OpenMetalWallpaper").appendingPathComponent("Wallpapers")
        try? FileManager.default.createDirectory(at: defaultPath, withIntermediateDirectories: true)
        return defaultPath
    }
    
    init() {
        restoreBookmarks()
        importFromFolder(url: storageURL)
    }
    
    // --- Import Logic ---
    func importVideoFile(url: URL, title: String) {
        let safeTitle = title.isEmpty ? url.deletingPathExtension().lastPathComponent : title
        let folderName = safeTitle.components(separatedBy: CharacterSet(charactersIn: "/\\?%*|\"<>:")).joined()
        let destinationFolder = storageURL.appendingPathComponent(folderName)
        let videoExt = url.pathExtension
        let destVideoURL = destinationFolder.appendingPathComponent("video.\(videoExt)")
        let destThumbURL = destinationFolder.appendingPathComponent("preview.jpg")
        let destJsonURL = destinationFolder.appendingPathComponent("project.json")
        
        do {
            try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destVideoURL.path) { try FileManager.default.removeItem(at: destVideoURL) }
            try FileManager.default.copyItem(at: url, to: destVideoURL)
            generateThumbnail(videoURL: destVideoURL, destination: destThumbURL)
            let newProject = WallpaperProject(title: safeTitle, file: "video.\(videoExt)", type: "video", preview: "preview.jpg", description: nil, absolutePath: nil, thumbnailPath: nil)
            let jsonData = try JSONEncoder().encode(newProject)
            try jsonData.write(to: destJsonURL)
            importFromFolder(url: destinationFolder)
        } catch { print("Import video failed: \(error)") }
    }
    
    private func generateThumbnail(videoURL: URL, destination: URL) {
        let asset = AVAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 1, preferredTimescale: 60)
        do {
            let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            let nsImage = NSImage(cgImage: cgImage, size: .zero)
            if let tiff = nsImage.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
                try jpeg.write(to: destination)
            }
        } catch { print("Thumbnail error: \(error)") }
    }
    
    func setStoragePath(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: storagePathKey)
        importFromFolder(url: url)
    }
    
    func importFromFolder(url: URL) {
        saveBookmark(for: url)
        let fileManager = FileManager.default
        let directJson = url.appendingPathComponent("project.json")
        if fileManager.fileExists(atPath: directJson.path) {
            parseProjectJSON(url: directJson)
            return
        }
        if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: nil) {
            for case let fileURL as URL in enumerator {
                if fileURL.lastPathComponent == "project.json" {
                    parseProjectJSON(url: fileURL)
                }
            }
        }
    }
    
    private func saveBookmark(for url: URL) {
        do {
            let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            var bookmarks = UserDefaults.standard.dictionary(forKey: bookmarksKey) as? [String: Data] ?? [:]
            bookmarks[url.absoluteString] = bookmarkData
            UserDefaults.standard.set(bookmarks, forKey: bookmarksKey)
        } catch { print("Bookmark error: \(error)") }
    }
    
    private func restoreBookmarks() {
        let bookmarks = UserDefaults.standard.dictionary(forKey: bookmarksKey) as? [String: Data] ?? [:]
        for (_, data) in bookmarks {
            var isStale = false
            do {
                let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                if url.startAccessingSecurityScopedResource() { importFromFolder(url: url) }
            } catch { print("Resolve error: \(error)") }
        }
    }
    
    func removeWallpaper(id: String, deleteFile: Bool) {
        guard let index = wallpapers.firstIndex(where: { $0.id == id }) else { return }
        let wallpaper = wallpapers[index]
        
        if deleteFile, let path = wallpaper.absolutePath {
            let folder = path.deletingLastPathComponent()
            do {
                try FileManager.default.removeItem(at: folder)
                print("Physically deleted: \(folder.path)")
            } catch {
                print("Delete file failed: \(error)")
            }
        }
        
        DispatchQueue.main.async {
            // 再次检查索引，防止异步期间数组变动
            if let verifyIndex = self.wallpapers.firstIndex(where: { $0.id == id }) {
                self.wallpapers.remove(at: verifyIndex)
                print("Removed from library list")
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
            if !wallpapers.contains(where: { $0.absolutePath == project.absolutePath }) {
                let type = project.type?.lowercased() ?? ""
                if type == "video" || type == "web" || type == "html" {
                    DispatchQueue.main.async { self.wallpapers.append(project) }
                }
            }
        } catch { }
    }
}
