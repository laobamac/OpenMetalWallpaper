/*
 File: SettingsView.swift
 Description: Settings with Audio Input Selection.
*/

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
    
    @StateObject private var launchManager = LaunchManager.shared
    @State private var showClearDataAlert = false
    @State private var inputDevices: [AVCaptureDevice] = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(NSLocalizedString("preferences_title", comment: "Preferences")).font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            Form {
                // Library
                Section(header: Text(NSLocalizedString("wallpaper_library_header", comment: ""))) {
                    HStack {
                        Image(systemName: "folder")
                        VStack(alignment: .leading) {
                            Text(NSLocalizedString("default_storage_location", comment: ""))
                            Text(library.storageURL.path).font(.caption).foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Button(NSLocalizedString("change_button", comment: "")) { chooseStorageFolder() }
                    }
                }
                
                // Performance & Audio
                Section(header: Text(NSLocalizedString("performance_header", comment: ""))) {
                    Toggle(NSLocalizedString("preload_video_memory", comment: ""), isOn: $loadToMemory)
                        .help(NSLocalizedString("preload_help", comment: ""))
                    
                    HStack {
                        Text(NSLocalizedString("frame_rate_limit", comment: ""))
                        Spacer()
                        Picker("", selection: $fpsLimit) {
                            Text("30 FPS").tag(30)
                            Text("60 FPS").tag(60)
                        }.pickerStyle(.menu).frame(width: 100)
                    }
                    
                    // Audio Input Picker
                    HStack {
                        Text("音频输入 (Audio Input)")
                        Spacer()
                        Picker("", selection: $audioDeviceID) {
                            Text("系统默认 (Default)").tag("")
                            ForEach(inputDevices, id: \.uniqueID) { device in
                                Text(device.localizedName).tag(device.uniqueID)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 200)
                        .onChange(of: audioDeviceID) {
                            // Notify Player to Restart Audio
                            NotificationCenter.default.post(name: Notification.Name("omw_audioDeviceChanged"), object: nil)
                        }
                    }
                }
                
                // Automation
                Section(header: Text(NSLocalizedString("automation_header", comment: ""))) {
                    Toggle(NSLocalizedString("pause_on_app_focus", comment: ""), isOn: $pauseOnAppFocus)
                    Toggle(NSLocalizedString("override_lock_screen", comment: ""), isOn: $overrideLockScreen)
                }
                
                // Maintenance
                Section(header: Text(NSLocalizedString("maintenance", comment: ""))) {
                    HStack {
                        Text(NSLocalizedString("clear_user_data", comment: ""))
                        Spacer()
                        Button(NSLocalizedString("clear_all", comment: "")) { showClearDataAlert = true }
                        .alert(isPresented: $showClearDataAlert) {
                            Alert(
                                title: Text(NSLocalizedString("confirm_clear_data", comment: "")),
                                primaryButton: .destructive(Text(NSLocalizedString("clear_button", comment: "")), action: {
                                    WallpaperPersistence.shared.deleteAllUserData()
                                }),
                                secondaryButton: .cancel()
                            )
                        }
                    }
                }
                
                // Updates
                Section(header: Text(NSLocalizedString("updates_header", comment: ""))) {
                    Toggle(NSLocalizedString("launch_at_login", comment: ""), isOn: $launchManager.isLaunchAtLoginEnabled)
                    Toggle(NSLocalizedString("auto_check_updates", comment: ""), isOn: $checkUpdateOnStartup)
                    HStack {
                        Text(String(format: NSLocalizedString("current_version_text", comment: ""), AppInfo.fullVersionString)).foregroundColor(.secondary)
                        Spacer()
                        Button(NSLocalizedString("check_updates_button", comment: "")) { UpdateChecker.shared.checkForUpdates(userInitiated: true) }
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
                Button(NSLocalizedString("done_button", comment: "")) {
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
