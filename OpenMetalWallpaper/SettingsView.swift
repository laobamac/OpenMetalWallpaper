/*
 License: AGPLv3
 Author: laobamac
 File: SettingsView.swift
 Description: Settings using dynamic AppInfo.
*/

import SwiftUI

struct SettingsView: View {
    @Environment(\.presentationMode) var presentationMode
    
    @AppStorage("omw_loadToMemory") private var loadToMemory: Bool = false
    @AppStorage("omw_pauseOnAppFocus") private var pauseOnAppFocus: Bool = false
    @AppStorage("omw_checkUpdateOnStartup") private var checkUpdateOnStartup: Bool = true
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("偏好设置")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // 内容区
            Form {
                Section {
                    Toggle("预加载视频到内存", isOn: $loadToMemory)
                        .help("减少磁盘IO，但增加内存占用")
                    
                    Text("启用此选项可消除循环播放时的卡顿，适合短视频。对于长视频建议关闭以节省内存。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 20)
                } header: {
                    Text("性能")
                }
                
                Section {
                    Toggle("其他应用全屏/活动时暂停", isOn: $pauseOnAppFocus)
                    Text("当焦点在其他窗口时暂停播放，节省 GPU 资源。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 20)
                } header: {
                    Text("自动化")
                }
                
                // 更新设置
                Section {
                    Toggle("启动时自动检查更新", isOn: $checkUpdateOnStartup)
                    
                    HStack {
                        // 动态读取版本号
                        Text("当前版本: \(AppInfo.fullVersionString)")
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button("检查更新") {
                            UpdateChecker.shared.checkForUpdates(userInitiated: true)
                        }
                    }
                    .padding(.top, 4)
                } header: {
                    Text("更新")
                }
                
                Section {
                    HStack {
                        Text(AppInfo.appName)
                        Spacer()
                        Text("AGPLv3 License")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("关于")
                }
            }
            .formStyle(.grouped)
            .frame(width: 450, height: 400)
            
            Divider()
            
            // 底部按钮
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
}
