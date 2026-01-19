/*
 License: AGPLv3
 Author: laobamac
 File: WallpaperLibrary.swift
 Description: Library with Web Support & Property Parsing.
*/

import Foundation
import Combine
import SwiftUI
import AVFoundation

// MARK: - JSON Structures
// 用于处理 JSON 中可能是 String 或 Number 的 value
enum AnyCodableValue: Codable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let x = try? container.decode(Double.self) { self = .number(x); return }
        if let x = try? container.decode(String.self) { self = .string(x); return }
        if let x = try? container.decode(Bool.self) { self = .bool(x); return }
        if container.decodeNil() { self = .null; return }
        throw DecodingError.typeMismatch(AnyCodableValue.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for AnyCodableValue"))
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let x): try container.encode(x)
        case .number(let x): try container.encode(x)
        case .bool(let x): try container.encode(x)
        case .null: try container.encodeNil()
        }
    }
    
    var rawValue: Any {
        switch self {
        case .string(let s): return s
        case .number(let n): return n
        case .bool(let b): return b
        case .null: return ""
        }
    }
    
    // 为了让 Picker 能使用 tag，先写一个明确的 Hashable 返回值
    var hashableRawValue: AnyHashable {
        switch self {
        case .string(let s): return AnyHashable(s)
        case .number(let n): return AnyHashable(n)
        case .bool(let b): return AnyHashable(b)
        case .null: return AnyHashable("")
        }
    }
}

// Hashable 协议
struct PropertyOption: Codable, Hashable {
    let label: String
    let value: AnyCodableValue
}

struct WallpaperPropertyConfig: Codable {
    let type: String
    let text: String?
    let value: AnyCodableValue?
    let min: Double?
    let max: Double?
    let options: [PropertyOption]?
    let order: Int?
}

struct WallpaperGeneral: Codable {
    let properties: [String: WallpaperPropertyConfig]?
}

struct WallpaperProject: Codable, Identifiable {
    var id: String { absolutePath?.path ?? (file ?? UUID().uuidString) }
    
    let title: String
    let file: String?
    let type: String?
    let preview: String?
    let description: String?
    let general: WallpaperGeneral? // [NEW]
    
    var absolutePath: URL?
    var thumbnailPath: URL?
    
    private enum CodingKeys: String, CodingKey {
        case title, file, type, preview, description, general
    }
}

class WallpaperLibrary: ObservableObject {
    @Published var wallpapers: [WallpaperProject] = []
    
    private let bookmarksKey = "omw_folder_bookmarks"
    private let storagePathKey = "omw_library_storage_path"
    
    var storageURL: URL {
        if let path = UserDefaults.standard.string(forKey: storagePathKey) { return URL(fileURLWithPath: path) }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let defaultPath = appSupport.appendingPathComponent("OpenMetalWallpaper").appendingPathComponent("Wallpapers")
        try? FileManager.default.createDirectory(at: defaultPath, withIntermediateDirectories: true)
        return defaultPath
    }
    
    init() {
        restoreBookmarks()
        importFromFolder(url: storageURL)
    }
    
    @discardableResult
    func importVideoFile(url: URL, title: String) -> Bool {
        // (Use previous logic)
        let safeTitle = title.isEmpty ? url.deletingPathExtension().lastPathComponent : title
        let folderName = safeTitle.components(separatedBy: CharacterSet(charactersIn: "/\\?%*|\"<>:")).joined()
        let destinationFolder = storageURL.appendingPathComponent(folderName)
        let videoExt = url.pathExtension
        do {
            try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: destinationFolder.appendingPathComponent("video.\(videoExt)"))
            // ... (Generate Thumb & JSON) ...
            let newProject = WallpaperProject(title: safeTitle, file: "video.\(videoExt)", type: "video", preview: "preview.jpg", description: nil, general: nil, absolutePath: nil, thumbnailPath: nil)
            let destJsonURL = destinationFolder.appendingPathComponent("project.json")
            try JSONEncoder().encode(newProject).write(to: destJsonURL)
            importFromFolder(url: destinationFolder)
            return true
        } catch { return false }
    }
    
    func setStoragePath(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: storagePathKey)
        importFromFolder(url: url)
    }

    func importFromFolder(url: URL) {
        saveBookmark(for: url)
        let fileManager = FileManager.default
        let directJson = url.appendingPathComponent("project.json")
        
        // Single wallpaper folder
        if fileManager.fileExists(atPath: directJson.path) {
            parseProjectJSON(url: directJson)
            return
        }
        
        // Folder containing multiple wallpapers
        var jsonFiles: [URL] = []
        if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                if fileURL.lastPathComponent == "project.json" {
                    jsonFiles.append(fileURL)
                }
            }
        }
        
        for fileURL in jsonFiles {
            parseProjectJSON(url: fileURL)
        }
        
        // MARK: - Fix: Sort Wallpapers
        // 确保每次启动顺序一致 (按标题排序)
        DispatchQueue.main.async {
            self.wallpapers.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }
    
    private func parseProjectJSON(url: URL) {
        do {
            let data = try Data(contentsOf: url)
            var project = try JSONDecoder().decode(WallpaperProject.self, from: data)
            let folder = url.deletingLastPathComponent()
            project.absolutePath = folder.appendingPathComponent(project.file ?? "index.html")
            if let preview = project.preview {
                project.thumbnailPath = folder.appendingPathComponent(preview)
            }
            
            DispatchQueue.main.async {
                if !self.wallpapers.contains(where: { $0.absolutePath == project.absolutePath }) {
                    let type = project.type?.lowercased() ?? ""
                    if type == "video" || type == "web" {
                        self.wallpapers.append(project)
                        // Trigger sort again after append
                        self.wallpapers.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                    }
                }
            }
        } catch {
            print("Parse Error: \(error)")
        }
    }
    
    private func saveBookmark(for url: URL) {
        do {
            let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            var bookmarks = UserDefaults.standard.dictionary(forKey: bookmarksKey) as? [String: Data] ?? [:]
            bookmarks[url.absoluteString] = bookmarkData
            UserDefaults.standard.set(bookmarks, forKey: bookmarksKey)
        } catch { }
    }
    
    private func restoreBookmarks() {
        let bookmarks = UserDefaults.standard.dictionary(forKey: bookmarksKey) as? [String: Data] ?? [:]
        for (_, data) in bookmarks {
            var isStale = false
            do {
                let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                if url.startAccessingSecurityScopedResource() { importFromFolder(url: url) }
            } catch { }
        }
    }
    
    func removeWallpaper(id: String, deleteFile: Bool) {
        guard let index = wallpapers.firstIndex(where: { $0.id == id }) else { return }
        let wallpaper = wallpapers[index]
        if deleteFile, let path = wallpaper.absolutePath {
            let folder = path.deletingLastPathComponent()
            do { try FileManager.default.removeItem(at: folder) } catch { }
        }
        DispatchQueue.main.async {
            if let verifyIndex = self.wallpapers.firstIndex(where: { $0.id == id }) {
                self.wallpapers.remove(at: verifyIndex)
            }
        }
    }
}
