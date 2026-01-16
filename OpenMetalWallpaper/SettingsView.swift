/*
 License: AGPLv3
 Author: laobamac
 File: SettingsView.swift
 Description: Settings with Library Path selection.
*/

import SwiftUI

struct SettingsView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var library: WallpaperLibrary
    
    @AppStorage("omw_loadToMemory") private var loadToMemory: Bool = false
    @AppStorage("omw_pauseOnAppFocus") private var pauseOnAppFocus: Bool = false
    @AppStorage("omw_checkUpdateOnStartup") private var checkUpdateOnStartup: Bool = true
    
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
                Section {
                    HStack {
                        Image(systemName: "folder")
                        VStack(alignment: .leading) {
                            Text("默认存储位置")
                            Text(library.storageURL.path)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Button("更改...") {
                            chooseStorageFolder()
                        }
                    }
                } header: {
                    Text("壁纸库")
                }
                
                Section {
                    Toggle("预加载视频到内存", isOn: $loadToMemory)
                        .help("减少磁盘IO，但增加内存占用")
                    Text("启用此选项可消除循环播放时的卡顿。")
                        .font(.caption).foregroundColor(.secondary)
                } header: {
                    Text("性能")
                }
                
                Section {
                    Toggle("其他应用全屏/活动时暂停", isOn: $pauseOnAppFocus)
                } header: {
                    Text("自动化")
                }
                
                Section {
                    Toggle("启动时自动检查更新", isOn: $checkUpdateOnStartup)
                    HStack {
                        Text("当前版本: \(AppInfo.fullVersionString)").foregroundColor(.secondary)
                        Spacer()
                        Button("检查更新") { UpdateChecker.shared.checkForUpdates(userInitiated: true) }
                    }
                } header: {
                    Text("更新")
                }
                
                Section {
                    HStack {
                        Text(AppInfo.appName)
                        Spacer()
                        Text("AGPLv3 License").foregroundColor(.secondary)
                    }
                } header: {
                    Text("关于")
                }
            }
            .formStyle(.grouped)
            .frame(width: 500, height: 450)
            
            Divider()
            
            HStack {
                Spacer()
                Button("完成") {
                    WallpaperEngine.shared.updateSettings()
                    presentationMode.wrappedValue.dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
    
    private func chooseStorageFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "选择一个新的文件夹来存储导入的壁纸"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                library.setStoragePath(url)
            }
        }
    }
}
