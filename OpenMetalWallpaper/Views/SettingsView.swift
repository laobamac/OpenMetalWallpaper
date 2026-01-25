//
//  SettingsView.swift
//  OpenMetalWallpaper
//
//  Created by laobamac on 2026/1/17.
//

import SwiftUI
import AVFoundation

struct SettingsView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var library: WallpaperLibrary
    
    @AppStorage("omw_loadToMemory") private var loadToMemory: Bool = false
    @AppStorage("omw_pauseOnAppFocus") private var pauseOnAppFocus: Bool = false
    @AppStorage("omw_checkUpdateOnStartup") private var checkUpdateOnStartup: Bool = true
    @AppStorage("omw_overrideLockScreen") private var overrideLockScreen: Bool = false
    @AppStorage("omw_fpsLimit") private var fpsLimit: Int = 60
    @AppStorage("omw_audioDeviceID") private var audioDeviceID: String = ""
    @AppStorage("omw_customSteamCMDPath") private var customSteamCMDPath: String = ""
    
    @StateObject private var launchManager = LaunchManager.shared
    @StateObject private var steam = SteamService.shared
    @State private var showClearDataAlert = false
    @State private var inputDevices: [AVCaptureDevice] = []
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("偏好设置").font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            Form {
                // 存储库
                Section(header: Text("壁纸库")) {
                    HStack {
                        Image(systemName: "folder")
                        VStack(alignment: .leading) {
                            Text("默认存储位置")
                            Text(library.storageURL.path).font(.caption).foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Button("更改...") { chooseStorageFolder() }
                    }
                }
                
                // Steam 创意工坊设置
                Section(header: Text("Steam 创意工坊")) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("SteamCMD 路径")
                            Text(steam.finalSteamCMDExecutable.path)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        if !customSteamCMDPath.isEmpty {
                            Button("重置") {
                                customSteamCMDPath = ""
                                steam.checkInstallation()
                            }
                        }
                        Button("选择文件...") { chooseSteamCMD() }
                    }
                    if !steam.isSteamCMDInstalled {
                        Text("未检测到有效的 SteamCMD，无法下载壁纸。")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                
                // 性能
                Section(header: Text("性能")) {
                    Toggle("预加载视频到内存", isOn: $loadToMemory)
                        .help("减少磁盘IO，但增加内存占用，可消除循环卡顿")
                    
                    HStack {
                        Text("帧率限制")
                        Spacer()
                        Picker("", selection: $fpsLimit) {
                            Text("30 FPS").tag(30)
                            Text("60 FPS").tag(60)
                        }.pickerStyle(.menu).frame(width: 100)
                    }
                    
                    HStack {
                        Text("音频输入")
                        Spacer()
                        Picker("", selection: $audioDeviceID) {
                            Text("系统默认").tag("")
                            ForEach(inputDevices, id: \.uniqueID) { device in
                                Text(device.localizedName).tag(device.uniqueID)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 200)
                        .onChange(of: audioDeviceID) {
                            NotificationCenter.default.post(name: Notification.Name("omw_audioDeviceChanged"), object: nil)
                        }
                    }
                }
                
                // 自动化
                Section(header: Text("自动化")) {
                    Toggle("其他应用全屏/活动时暂停", isOn: $pauseOnAppFocus)
                    Toggle("覆盖锁屏壁纸", isOn: $overrideLockScreen)
                }
                
                // 维护
                Section(header: Text("系统维护")) {
                    HStack {
                        Text("清理用户数据")
                        Spacer()
                        Button("全部清除") { showClearDataAlert = true }
                        .alert(isPresented: $showClearDataAlert) {
                            Alert(
                                title: Text("确认清除数据"),
                                message: Text("这将重置所有壁纸设置，但不会删除壁纸文件。"),
                                primaryButton: .destructive(Text("清除"), action: {
                                    WallpaperPersistence.shared.deleteAllUserData()
                                }),
                                secondaryButton: .cancel()
                            )
                        }
                    }
                }
                
                // 更新
                Section(header: Text("更新")) {
                    Toggle("开机自动启动", isOn: $launchManager.isLaunchAtLoginEnabled)
                    Toggle("启动时自动检查更新", isOn: $checkUpdateOnStartup)
                    HStack {
                        Text("当前版本: \(AppInfo.fullVersionString)").foregroundColor(.secondary)
                        Spacer()
                        Button("检查更新") { UpdateChecker.shared.checkForUpdates(userInitiated: true) }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(width: 500, height: 650)
            .onAppear {
                self.inputDevices = AudioSpectrumAnalyzer.getAvailableDevices()
            }
            
            Divider()
            
            HStack {
                Spacer()
                Button("完成") {
                    WallpaperEngine.shared.updateSettings()
                    presentationMode.wrappedValue.dismiss()
                }.keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
    
    private func chooseStorageFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.begin { response in
            if response == .OK, let url = panel.url { library.setStoragePath(url) }
        }
    }
    
    private func chooseSteamCMD() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "选择 steamcmd.sh"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                if url.lastPathComponent == "steamcmd.sh" {
                    customSteamCMDPath = url.path
                    steam.checkInstallation()
                }
            }
        }
    }
}
