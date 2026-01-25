//
//  WallpaperLibrary.swift
//  OpenMetalWallpaper
//
//  Created by laobamac on 2026/1/17.
//

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
    
    // --- [New] Scene Wallpaper Import Logic ---
    
    func importSceneWallpaper(url: URL, reportProgress: @escaping (String) -> Void, completion: @escaping (Bool, String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            reportProgress("Analyzing input...")
            
            let fileManager = FileManager.default
            let wallpaperName = url.lastPathComponent
            let destinationFolder = self.storageURL.appendingPathComponent(wallpaperName)
            
            // Identify Source Type
            var pkgFile: URL? = nil
            var isFolder = false
            
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                isFolder = isDirectory.boolValue
            }
            
            // Determine operation
            if !isFolder && url.pathExtension == "pkg" {
                pkgFile = url
            } else if isFolder {
                let checkPkg = url.appendingPathComponent("scene.pkg")
                if fileManager.fileExists(atPath: checkPkg.path) {
                    pkgFile = checkPkg
                }
            }
            
            // Unpack or Copy
            do {
                if fileManager.fileExists(atPath: destinationFolder.path) {
                    // Cleanup existing if overwrite needed, or fail. For now, assume overwrite.
                    try? fileManager.removeItem(at: destinationFolder)
                }
                
                if let pkg = pkgFile {
                    reportProgress("Unpacking scene.pkg...")
                    guard let parserPath = Bundle.main.url(forResource: "pkg_parser", withExtension: nil) else {
                        DispatchQueue.main.async { completion(false, "Missing pkg_parser tool.") }; return
                    }
                    
                    // Call pkg_parser <scene.pkg> <destination_folder>
                    let process = Process()
                    process.executableURL = parserPath
                    process.arguments = [pkg.path, destinationFolder.path]
                    
                    try process.run()
                    process.waitUntilExit()
                    
                    if process.terminationStatus != 0 {
                        DispatchQueue.main.async { completion(false, "pkg_parser failed with code \(process.terminationStatus).") }; return
                    }
                } else {
                    // Folder without pkg (already unpacked?), just copy
                    reportProgress("Copying files...")
                    try fileManager.copyItem(at: url, to: destinationFolder)
                }
                
                // Parse Models (if models folder exists)
                let modelsFolder = destinationFolder.appendingPathComponent("models")
                if fileManager.fileExists(atPath: modelsFolder.path) {
                    // Check for .mdl files
                    if let enumerator = fileManager.enumerator(at: modelsFolder, includingPropertiesForKeys: nil) {
                        var hasMdl = false
                        for case let fileURL as URL in enumerator {
                            if fileURL.pathExtension == "mdl" { hasMdl = true; break }
                        }
                        
                        if hasMdl {
                            reportProgress("Converting models...")
                            guard let mdlParserPath = Bundle.main.url(forResource: "mdl_parser", withExtension: nil) else {
                                DispatchQueue.main.async { completion(false, "Missing mdl_parser tool.") }; return
                            }
                            
                            // Call mdl_parser <models_folder>
                            let process = Process()
                            process.executableURL = mdlParserPath
                            process.arguments = [modelsFolder.path]
                            
                            try process.run()
                            process.waitUntilExit()
                            // We ignore errors here as some models might fail but others work
                        }
                    }
                }
                
                // Handle Thumbnail & Finalize
                reportProgress("Finalizing...")
                let projectJsonURL = destinationFolder.appendingPathComponent("project.json")
                if fileManager.fileExists(atPath: projectJsonURL.path) {
                    // Assuming project.json exists and is valid, WallpaperLibrary will parse it on reload
                    self.importFromFolder(url: destinationFolder)
                    DispatchQueue.main.async { completion(true, "Wallpaper imported successfully.") }
                } else {
                    DispatchQueue.main.async { completion(false, "Invalid scene wallpaper: missing project.json") }
                }
                
            } catch {
                DispatchQueue.main.async { completion(false, "Import failed: \(error.localizedDescription)") }
            }
        }
    }
    
    @discardableResult
    func importVideoFile(url: URL, title: String) -> Bool {
        // (Use existing logic from file_content_fetcher response)
        let safeTitle = title.isEmpty ? url.deletingPathExtension().lastPathComponent : title
        let folderName = safeTitle.components(separatedBy: CharacterSet(charactersIn: "/\\?%*|\"<>:")).joined()
        let destinationFolder = storageURL.appendingPathComponent(folderName)
        let videoExt = url.pathExtension
        do {
            try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: destinationFolder.appendingPathComponent("video.\(videoExt)"))
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
        
        if fileManager.fileExists(atPath: directJson.path) {
            parseProjectJSON(url: directJson)
            return
        }
        
        var jsonFiles: [URL] = []
        if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                if fileURL.lastPathComponent == "project.json" {
                    jsonFiles.append(fileURL)
                }
            }
        }
        
        for fileURL in jsonFiles { parseProjectJSON(url: fileURL) }
        
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
            
            // Validate absolute path existence
            if let path = project.absolutePath, !FileManager.default.fileExists(atPath: path.path) {
                // Some project.jsons might point to .json files inside for scene, which is fine
                // But if file is missing completely, we might warn.
            }

            if let preview = project.preview {
                project.thumbnailPath = folder.appendingPathComponent(preview)
            }
            
            DispatchQueue.main.async {
                if !self.wallpapers.contains(where: { $0.absolutePath == project.absolutePath }) {
                    let type = project.type?.lowercased() ?? ""
                    // Accept 'scene' type
                    if type == "video" || type == "web" || type == "scene" {
                        self.wallpapers.append(project)
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
