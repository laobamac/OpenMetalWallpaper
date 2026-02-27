//
//  SteamService.swift
//  OpenMetalWallpaper
//
//  Created by laobamac on 2026/1/17.
//

import Foundation
import Combine
import SwiftUI

struct SteamWorkshopItem: Identifiable, Hashable {
    let id: String
    let title: String
    let previewURL: URL?
    let author: String
    let description: String
    let type: String
    let tags: [String]
}

enum SteamLoginResult {
    case success
    case needTwoFactor
    case failed(String)
}

class SteamService: ObservableObject {
    static let shared = SteamService()
    
    @AppStorage("omw_customSteamCMDPath") var customSteamCMDPath: String = ""
    @AppStorage("omw_steamUsername") var steamUsername: String = ""
    
    @Published var isSteamLoggedIn: Bool = false
    @Published var isSteamCMDInstalled = false
    
    @Published var isDownloading = false
    @Published var downloadProgressText: String = ""
    @Published var downloadProgressValue: Double = 0.0
    @Published var realtimeLog: String = ""
    
    @Published var isLoggingIn = false
    @Published var loginStatus: String = "准备就绪"
    
    // 全局阻断状态 (用于安装/更新)
    @Published var isGlobalWorking: Bool = false
    @Published var globalWorkText: String = ""
    
    @Published var logs: [String] = []
    
    private var responseCache: [String: [SteamWorkshopItem]] = [:]
    private var currentProcess: Process?
    
    private let appID = "431960"
    private let steamCMDDownloadURL = URL(string: "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_osx.tar.gz")!
    
    private var appSupportURL: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("OpenMetalWallpaper")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    
    private var defaultSteamCMDFolder: URL {
        appSupportURL.appendingPathComponent("SteamCMD")
    }
    
    private var defaultSteamCMDExecutable: URL {
        defaultSteamCMDFolder.appendingPathComponent("steamcmd.sh")
    }
    
    var finalSteamCMDExecutable: URL {
        if !customSteamCMDPath.isEmpty {
            return URL(fileURLWithPath: customSteamCMDPath)
        }
        return defaultSteamCMDExecutable
    }
    
    init() {
        checkInstallation()
        if !steamUsername.isEmpty {
            isSteamLoggedIn = true
        }
    }
    
    private func log(_ message: String) {
        let logMsg = "[Steam] \(message)"
        print(logMsg)
        DispatchQueue.main.async {
            if self.logs.count > 500 { self.logs.removeFirst() }
            self.logs.append(logMsg)
        }
    }
    
    func checkInstallation() {
        let path = finalSteamCMDExecutable.path
        let exists = FileManager.default.fileExists(atPath: path)
        DispatchQueue.main.async { self.isSteamCMDInstalled = exists }
    }
    
    func installSteamCMD() {
        guard !isSteamCMDInstalled else { return }
        
        DispatchQueue.main.async {
            self.isGlobalWorking = true
            self.globalWorkText = "正在下载 SteamCMD 组件..."
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try FileManager.default.createDirectory(at: self.defaultSteamCMDFolder, withIntermediateDirectories: true)
                let tarPath = self.defaultSteamCMDFolder.appendingPathComponent("steamcmd.tar.gz")
                let data = try Data(contentsOf: self.steamCMDDownloadURL)
                try data.write(to: tarPath)
                
                DispatchQueue.main.async { self.globalWorkText = "正在解压文件..." }
                
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
                process.arguments = ["-xvzf", tarPath.path, "-C", self.defaultSteamCMDFolder.path]
                try process.run()
                process.waitUntilExit()
                
                let chmod = Process()
                chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
                chmod.arguments = ["+x", self.defaultSteamCMDExecutable.path]
                try chmod.run()
                chmod.waitUntilExit()
                
                try? FileManager.default.removeItem(at: tarPath)
                
                // 首次运行更新 (关键步骤)
                DispatchQueue.main.async { self.globalWorkText = "首次运行：正在更新 SteamCMD (可能需要几分钟)..." }
                
                let updateProcess = Process()
                updateProcess.executableURL = self.defaultSteamCMDExecutable
                updateProcess.arguments = ["+quit"]
                
                let pipe = Pipe()
                updateProcess.standardOutput = pipe
                updateProcess.standardError = pipe
                
                try updateProcess.run()
                
                let handle = pipe.fileHandleForReading
                handle.readabilityHandler = { p in
                    if let line = String(data: p.availableData, encoding: .utf8) {
                        print("[Install] \(line.trimmingCharacters(in: .whitespacesAndNewlines))")
                    }
                }
                
                updateProcess.waitUntilExit()
                handle.readabilityHandler = nil
                
                DispatchQueue.main.async {
                    self.customSteamCMDPath = ""
                    self.checkInstallation()
                    self.isGlobalWorking = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.isGlobalWorking = false
                    // 这里可以通过 logs 或者弹窗通知错误，但为了保持逻辑简单，先打印
                    print("安装失败: \(error)")
                }
            }
        }
    }
    
    func logout() {
        steamUsername = ""
        isSteamLoggedIn = false
        log("用户登出")
    }
    
    func cancelCurrentTask() {
        DispatchQueue.main.async {
            self.isDownloading = false
            self.isLoggingIn = false
            self.realtimeLog += "\n[用户已取消]"
            self.loginStatus = "已取消"
        }
        
        if let process = currentProcess {
            if process.isRunning {
                process.terminate()
                log("进程已强制终止")
            }
        }
        currentProcess = nil
    }
    
    func completeTask() {
        DispatchQueue.main.async {
            self.isDownloading = false
            self.currentProcess = nil
            self.downloadProgressText = ""
            self.downloadProgressValue = 0.0
        }
    }
    
    func appendLog(_ text: String) {
        DispatchQueue.main.async {
            self.realtimeLog += "\n" + text
        }
    }
    
    func updateProgress(text: String, value: Double) {
        DispatchQueue.main.async {
            self.downloadProgressText = text
            self.downloadProgressValue = value
        }
    }
    
    func fetchWorkshopItems(page: Int, searchText: String, type: String, genre: String, sort: String, forceRefresh: Bool, completion: @escaping ([SteamWorkshopItem]) -> Void) {
        let cacheKey = "\(page)-\(searchText)-\(type)-\(genre)-\(sort)"
        
        // 如果不是强制刷新，且有缓存，直接返回
        if !forceRefresh, let cached = responseCache[cacheKey] {
            completion(cached)
            return
        }
        
        var components = URLComponents(string: "https://steamcommunity.com/workshop/browse/")!
        var queryItems = [
            URLQueryItem(name: "appid", value: appID),
            URLQueryItem(name: "p", value: "\(page)"),
            URLQueryItem(name: "browsesort", value: sort),
            URLQueryItem(name: "section", value: "readytouseitems"),
            URLQueryItem(name: "actualsection", value: "readytouseitems")
        ]
        
        if !searchText.isEmpty {
            queryItems.append(URLQueryItem(name: "searchtext", value: searchText))
            queryItems.append(URLQueryItem(name: "childpublishedfileid", value: "0"))
        }
        if type != "all" { queryItems.append(URLQueryItem(name: "requiredtags[]", value: type)) }
        if genre != "all" { queryItems.append(URLQueryItem(name: "requiredtags[]", value: genre)) }
        
        components.queryItems = queryItems
        guard let url = components.url else { completion([]); return }
        
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data, let html = String(data: data, encoding: .utf8) else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            let items = self.parseHTML(html)
            DispatchQueue.main.async {
                self.responseCache[cacheKey] = items
                completion(items)
            }
        }.resume()
    }
    
    private func parseHTML(_ html: String) -> [SteamWorkshopItem] {
        var items: [SteamWorkshopItem] = []
        let nsString = html as NSString
        let jsonPattern = #"SharedFileBindMouseHover\s*\(\s*"sharedfile_(\d+)"\s*,\s*false\s*,\s*(\{.*?\})\s*\);"#
        
        do {
            let regex = try NSRegularExpression(pattern: jsonPattern, options: [.dotMatchesLineSeparators])
            let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: nsString.length))
            
            for match in matches {
                let id = nsString.substring(with: match.range(at: 1))
                let jsonStr = nsString.substring(with: match.range(at: 2))
                
                if let jsonData = jsonStr.data(using: .utf8),
                   let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    
                    let title = dict["title"] as? String ?? "Unknown"
                    let description = (dict["description"] as? String ?? "").replacingOccurrences(of: "<br>", with: "\n").replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&amp;", with: "&")
                    
                    var previewURL: URL? = nil
                    let imgPattern = #"<div id="sharedfile_\#(id)"[^>]*>[\s\S]*?<img[^>]+src="([^"]+)""#
                    if let imgRegex = try? NSRegularExpression(pattern: imgPattern, options: []),
                       let imgMatch = imgRegex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: nsString.length)) {
                        let urlStr = nsString.substring(with: imgMatch.range(at: 1))
                        previewURL = URL(string: urlStr)
                    }
                    
                    var author = "Steam User"
                    let searchRangeStart = match.range.location
                    let searchLength = min(3000, nsString.length - searchRangeStart)
                    let searchRange = NSRange(location: searchRangeStart, length: searchLength)
                    let searchBlock = nsString.substring(with: searchRange)
                    
                    if let authorRange = searchBlock.range(of: "workshopItemAuthorName"),
                       let linkStart = searchBlock.range(of: "<a", options: [], range: authorRange.upperBound..<searchBlock.endIndex),
                       let linkEnd = searchBlock.range(of: "</a>", options: [], range: linkStart.upperBound..<searchBlock.endIndex),
                       let contentStart = searchBlock.range(of: ">", options: [], range: linkStart.upperBound..<linkEnd.lowerBound) {
                        author = String(searchBlock[contentStart.upperBound..<linkEnd.lowerBound])
                    }
                    
                    var type = "Video"
                    let lowerTitle = title.lowercased()
                    let lowerDesc = description.lowercased()
                    if lowerTitle.contains("scene") || lowerDesc.contains("scene") { type = "Scene" }
                    if lowerTitle.contains("web") || lowerDesc.contains("web") || lowerDesc.contains("html") { type = "Web" }
                    if lowerTitle.contains("audio") { type = "Audio" }
                    
                    items.append(SteamWorkshopItem(id: id, title: title, previewURL: previewURL, author: author, description: description, type: type, tags: []))
                }
            }
        } catch {}
        return items
    }
    
    func loginToSteam(username: String, password: String, twoFactor: String?, completion: @escaping (SteamLoginResult) -> Void) {
        guard isSteamCMDInstalled else { completion(.failed("未安装")); return }
        
        isLoggingIn = true
        realtimeLog = ""
        DispatchQueue.main.async { self.loginStatus = "正在连接 Steam 服务器..." }
        log("开始登录: \(username)")
        
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            self.currentProcess = process
            process.executableURL = self.finalSteamCMDExecutable
            
            var args = ["+login", username, password]
            if let code = twoFactor, !code.isEmpty { args.append(code) }
            args.append("+quit")
            process.arguments = args
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            do {
                try process.run()
                let handle = pipe.fileHandleForReading
                handle.readabilityHandler = { fileHandle in
                    if !self.isLoggingIn {
                        fileHandle.readabilityHandler = nil
                        return
                    }
                    
                    let data = fileHandle.availableData
                    if data.isEmpty { return }
                    if let line = String(data: data, encoding: .utf8) {
                        DispatchQueue.main.async { self.realtimeLog += line }
                        print("[SteamCMD Login] \(line)", terminator: "")
                        
                        if line.contains("Waiting for confirmation") {
                            DispatchQueue.main.async { self.loginStatus = "请在手机 Steam 应用上确认登录..." }
                        } else if line.contains("Logging in user") {
                            DispatchQueue.main.async { self.loginStatus = "正在验证账户..." }
                        } else if line.contains("Enter the current code") || line.contains("Enter the special access code") {
                            DispatchQueue.main.async {
                                self.loginStatus = "需要验证码"
                                self.isLoggingIn = false
                                completion(.needTwoFactor)
                            }
                            fileHandle.readabilityHandler = nil
                            return
                        } else if line.contains("Logged in OK") || line.contains("Waiting for user info...OK") {
                            DispatchQueue.main.async {
                                self.loginStatus = "登录成功"
                                self.steamUsername = username
                                self.isSteamLoggedIn = true
                                self.isLoggingIn = false
                                completion(.success)
                            }
                            fileHandle.readabilityHandler = nil
                            return
                        } else if line.contains("Invalid Password") {
                            DispatchQueue.main.async {
                                self.isLoggingIn = false
                                completion(.failed("密码错误"))
                            }
                            fileHandle.readabilityHandler = nil
                            return
                        } else if line.contains("Rate Limit") {
                            DispatchQueue.main.async {
                                self.isLoggingIn = false
                                completion(.failed("尝试次数过多，请稍后再试"))
                            }
                            fileHandle.readabilityHandler = nil
                            return
                        }
                    }
                }
                process.waitUntilExit()
                
                if self.isLoggingIn {
                    DispatchQueue.main.async {
                        self.isLoggingIn = false
                        if !self.loginStatus.contains("手机") {
                            completion(.failed("登录连接断开"))
                        }
                    }
                }
                
            } catch {
                DispatchQueue.main.async {
                    self.isLoggingIn = false
                    self.currentProcess = nil
                    completion(.failed(error.localizedDescription))
                }
            }
        }
    }
    
    func downloadItem(id: String, completion: @escaping (Bool, URL?) -> Void) {
        guard isSteamCMDInstalled else { completion(false, nil); return }
        
        isDownloading = true
        realtimeLog = ">>> 准备下载 Item \(id)\n"
        log("下载: \(id)")
        
        let installDir = self.defaultSteamCMDFolder.path
        
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            self.currentProcess = process
            process.executableURL = self.finalSteamCMDExecutable
            
            // 优化：尝试使用 cached login (不带密码)
            let loginArg = (!self.steamUsername.isEmpty) ? self.steamUsername : "anonymous"
            
            process.arguments = [
                "+force_install_dir", installDir,
                "+login", loginArg,
                "+workshop_download_item", self.appID, id,
                "+quit"
            ]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            do {
                try process.run()
                
                let handle = pipe.fileHandleForReading
                handle.readabilityHandler = { fileHandle in
                    if !self.isDownloading {
                        fileHandle.readabilityHandler = nil
                        return
                    }
                    let data = fileHandle.availableData
                    guard !data.isEmpty else { return }
                    if let line = String(data: data, encoding: .utf8) {
                        DispatchQueue.main.async { self.realtimeLog += line }
                        print("[SteamCMD Download] \(line)", terminator: "")
                    }
                }
                
                process.waitUntilExit()
                handle.readabilityHandler = nil
                
                if !self.isDownloading { return }
                
                DispatchQueue.main.async {
                    let itemPath = self.defaultSteamCMDFolder.appendingPathComponent("steamapps/workshop/content/\(self.appID)/\(id)")
                    
                    if self.realtimeLog.contains("Access Denied") || self.realtimeLog.contains("No subscription") || self.realtimeLog.contains("Invalid Password") {
                        self.realtimeLog += "\n[错误] 鉴权失败，请在设置中重新登录"
                        completion(false, nil)
                        return
                    }
                    
                    var isSuccess = false
                    if FileManager.default.fileExists(atPath: itemPath.path) {
                        if let subs = try? FileManager.default.contentsOfDirectory(atPath: itemPath.path), !subs.isEmpty {
                            isSuccess = true
                        }
                    }
                    
                    if isSuccess {
                        self.realtimeLog += "\n[系统] 下载校验通过，准备导入..."
                        self.downloadProgressText = "正在导入..."
                        completion(true, itemPath)
                    } else {
                        self.realtimeLog += "\n[错误] 文件校验失败"
                        completion(false, nil)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isDownloading = false
                    self.currentProcess = nil
                    self.realtimeLog += "\n[异常] \(error.localizedDescription)"
                    completion(false, nil)
                }
            }
        }
    }
}
