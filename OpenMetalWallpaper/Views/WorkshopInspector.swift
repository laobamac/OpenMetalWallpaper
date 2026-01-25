//
//  WorkshopInspector.swift
//  OpenMetalWallpaper
//
//  Created by laobamac on 2026/1/17.
//

import SwiftUI

struct WorkshopInspector: View {
    let item: SteamWorkshopItem
    @EnvironmentObject var library: WallpaperLibrary
    @StateObject private var steam = SteamService.shared
    
    @State private var showLoginSheet = false
    @State private var showConsole = false
    @State private var username = ""
    @State private var password = ""
    @State private var twoFactorCode = ""
    @State private var loginMessage = ""
    @State private var isLoginSuccess = false
    @State private var loginState: LoginStep = .credentials
    
    enum LoginStep { case credentials, twoFactor }
    
    var isDownloaded: Bool {
        return library.wallpapers.contains { $0.absolutePath?.path.contains(item.id) ?? false }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                AsyncImage(url: item.previewURL) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fit).cornerRadius(12).shadow(radius: 8)
                    } else {
                        Rectangle().fill(Color.gray.opacity(0.1)).aspectRatio(16/9, contentMode: .fit).cornerRadius(12).overlay(ProgressView())
                    }
                }.frame(maxWidth: .infinity)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.title).font(.title2).bold().textSelection(.enabled)
                    HStack {
                        Label(item.author, systemImage: "person.fill").font(.subheadline).foregroundColor(.accentColor)
                        Spacer()
                        Text(item.type).font(.caption).fontWeight(.bold).padding(6).background(Color.secondary.opacity(0.1)).cornerRadius(4)
                        Text("ID: \(item.id)").font(.caption).monospacedDigit().foregroundColor(.gray).textSelection(.enabled)
                    }
                }
                
                Divider()
                
                if !item.description.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("简介").font(.headline)
                        Text(item.description).font(.body).foregroundColor(.secondary).lineLimit(15).textSelection(.enabled)
                    }
                    Divider()
                }
                
                VStack(spacing: 16) {
                    if steam.isDownloading {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("正在下载...").font(.headline)
                                Spacer()
                                ProgressView().scaleEffect(0.8)
                            }
                            Text("进度请查看实时日志。").font(.caption2).foregroundColor(.secondary)
                            
                            Button(action: { showConsole.toggle() }) {
                                HStack {
                                    Image(systemName: "terminal")
                                    Text(showConsole ? "隐藏详细日志" : "查看实时日志 (推荐)")
                                }
                            }
                            
                            if showConsole {
                                ScrollViewReader { proxy in
                                    ScrollView {
                                        Text(steam.realtimeLog)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.green)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .id("logBottom")
                                    }
                                    .frame(height: 150)
                                    .background(Color.black)
                                    .cornerRadius(8)
                                    .onChange(of: steam.realtimeLog) { _ in
                                        proxy.scrollTo("logBottom", anchor: .bottom)
                                    }
                                }
                            }
                            
                            HStack {
                                Spacer()
                                Button("取消下载") { steam.cancelCurrentTask() }.foregroundColor(.red)
                            }
                        }
                        .padding().background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)).cornerRadius(12)
                        
                    } else if isDownloaded {
                        HStack {
                            Image(systemName: "checkmark.circle.fill").font(.title2).foregroundColor(.green)
                            VStack(alignment: .leading) {
                                Text("已订阅").font(.headline)
                                Text("已在库中").font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding().background(Color.green.opacity(0.1)).cornerRadius(12)
                        
                    } else {
                        Button(action: { handleDownload() }) {
                            HStack { Image(systemName: "square.and.arrow.down.fill"); Text("订阅并下载").fontWeight(.semibold) }
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large).tint(.accentColor)
                    }
                    
                    if steam.isSteamLoggedIn {
                        HStack {
                            Image(systemName: "person.crop.circle.badge.checkmark").foregroundColor(.green)
                            Text(steam.steamUsername).fontWeight(.medium)
                            Spacer()
                            Button("退出登录") { steam.logout() }.buttonStyle(.borderless).foregroundColor(.red).font(.caption)
                        }
                        .padding(10).background(VisualEffectView(material: .contentBackground, blendingMode: .withinWindow)).cornerRadius(8)
                    } else {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                            Text("必须登录且拥有 Wallpaper Engine").font(.caption)
                            Spacer()
                            Button("去登录") {
                                username = steam.steamUsername
                                showLoginSheet = true
                            }
                            .buttonStyle(.bordered).controlSize(.small)
                        }
                        .padding(10).background(Color.orange.opacity(0.1)).cornerRadius(8)
                    }
                }
                Spacer()
            }.padding(24)
        }
        .sheet(isPresented: $showLoginSheet) {
            VStack(spacing: 24) {
                HStack {
                    Button("取消") {
                        steam.cancelCurrentTask()
                        showLoginSheet = false
                    }.buttonStyle(.borderless).foregroundColor(.secondary)
                    Spacer()
                }
                
                Image(systemName: "person.badge.key.fill").font(.system(size: 40)).foregroundColor(.accentColor).padding(.top)
                Text(loginState == .credentials ? "登录 SteamCMD" : "输入验证码").font(.title3).bold()
                
                VStack(spacing: 12) {
                    if loginState == .credentials {
                        TextField("用户名", text: $username).textFieldStyle(.roundedBorder).controlSize(.large)
                        SecureField("密码", text: $password).textFieldStyle(.roundedBorder).controlSize(.large)
                    } else {
                        Text("Steam 令牌/邮件验证码已发送，请输入：").font(.caption).foregroundColor(.secondary)
                        TextField("验证码", text: $twoFactorCode).textFieldStyle(.roundedBorder).controlSize(.large)
                    }
                }.padding(.horizontal)
                
                if steam.isLoggingIn {
                    VStack(spacing: 12) {
                        ProgressView().scaleEffect(0.8)
                        Text(steam.loginStatus) // 实时显示：请在手机确认 / 正在验证...
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .animation(.default, value: steam.loginStatus)
                        
                        Button("取消") { steam.cancelCurrentTask() }
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    .padding()
                } else {
                    if !loginMessage.isEmpty { Text(loginMessage).foregroundColor(isLoginSuccess ? .green : .red).font(.caption) }
                    
                    HStack(spacing: 16) {
                        if loginState == .credentials {
                            Button("下一步") {
                                performLogin()
                            }.buttonStyle(.borderedProminent).controlSize(.large).disabled(username.isEmpty || password.isEmpty).keyboardShortcut(.defaultAction)
                        } else {
                            Button("验证") {
                                performLogin()
                            }.buttonStyle(.borderedProminent).controlSize(.large).disabled(twoFactorCode.isEmpty).keyboardShortcut(.defaultAction)
                        }
                    }
                }
            }
            .padding()
            .frame(width: 350)
            .onAppear {
                // 每次打开时重置状态
                loginState = .credentials
                password = ""
                twoFactorCode = ""
                loginMessage = ""
                isLoginSuccess = false
                steam.loginStatus = "准备就绪"
            }
        }
    }
    
    private func performLogin() {
        steam.loginToSteam(username: username, password: password, twoFactor: twoFactorCode) { result in
            switch result {
            case .success:
                isLoginSuccess = true
                loginMessage = "登录成功"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { showLoginSheet = false }
            case .needTwoFactor:
                isLoginSuccess = false
                loginMessage = "请输入验证码"
                withAnimation { loginState = .twoFactor }
            case .failed(let msg):
                isLoginSuccess = false
                loginMessage = msg
            }
        }
    }
    
    private func handleDownload() {
        if !steam.isSteamLoggedIn {
            showLoginSheet = true
        } else {
            showConsole = true
            steam.downloadItem(id: item.id) { success, path in
                if success, let path = path {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: Notification.Name("omw_steam_download_complete"), object: nil, userInfo: ["path": path, "type": item.type])
                    }
                }
            }
        }
    }
}
