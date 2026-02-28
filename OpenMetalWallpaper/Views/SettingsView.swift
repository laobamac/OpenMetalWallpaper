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
    
    @State private var showFactoryResetAlert = false
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
                
                Section(header: Text("性能")) {
                    Toggle("预加载视频到内存", isOn: $loadToMemory)
                    
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
                
                Section(header: Text("自动化")) {
                    Toggle("其他应用全屏/活动时暂停", isOn: $pauseOnAppFocus)
                    Toggle("覆盖锁屏壁纸", isOn: $overrideLockScreen)
                }
                
                Section(header: Text("系统维护")) {
                    HStack {
                        Text("恢复出厂")
                        Spacer()
                        Button("执行") { showFactoryResetAlert = true }
                        .alert(isPresented: $showFactoryResetAlert) {
                            Alert(
                                title: Text("确认恢复出厂设置？"),
                                message: Text("这将移除所有设置并将存储在设定路径下的壁纸文件彻底删除，其他路径下的壁纸仅移除列表引用。软件将自动退出，该操作不可逆！"),
                                primaryButton: .destructive(Text("恢复出厂"), action: {
                                    library.factoryReset()
                                    WallpaperPersistence.shared.factoryResetSettings()
                                    NSApplication.shared.terminate(nil)
                                }),
                                secondaryButton: .cancel(Text("取消"))
                            )
                        }
                    }
                }
                
                Section(header: Text("更新")) {
                    Toggle("启动时自动检查更新", isOn: $checkUpdateOnStartup)
                    HStack {
                        Text("当前版本: \(AppInfo.fullVersionString)").foregroundColor(.secondary)
                        Spacer()
                        Button("检查更新") { UpdateChecker.shared.checkForUpdates(userInitiated: true) }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(width: 500, height: 600)
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
}
