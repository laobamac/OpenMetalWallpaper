/*
 License: AGPLv3
 Author: laobamac
 File: SettingsView.swift
 Description: Settings with Clear Data Button.
*/

import SwiftUI

struct SettingsView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var library: WallpaperLibrary
    
    @AppStorage("omw_loadToMemory") private var loadToMemory: Bool = false
    @AppStorage("omw_pauseOnAppFocus") private var pauseOnAppFocus: Bool = false
    @AppStorage("omw_checkUpdateOnStartup") private var checkUpdateOnStartup: Bool = true
    @AppStorage("omw_overrideLockScreen") private var overrideLockScreen: Bool = false
    @StateObject private var launchManager = LaunchManager.shared
    
    @State private var showClearDataAlert = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(NSLocalizedString("preferences_title", comment: "")).font(.headline)
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
                            Text(NSLocalizedString("default_storage_location", comment: ""))
                            Text(library.storageURL.path)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Button(NSLocalizedString("change_button", comment: "")) {
                            chooseStorageFolder()
                        }
                    }
                } header: {
                    Text(NSLocalizedString("wallpaper_library_header", comment: ""))
                }
                
                Section {
                    Toggle(NSLocalizedString("preload_video_memory", comment: ""), isOn: $loadToMemory)
                        .help(NSLocalizedString("preload_help", comment: ""))
                    Text(NSLocalizedString("preload_description", comment: ""))
                        .font(.caption).foregroundColor(.secondary)
                } header: {
                    Text(NSLocalizedString("performance_header", comment: ""))
                }
                
                Section {
                    Toggle(NSLocalizedString("pause_on_app_focus", comment: ""), isOn: $pauseOnAppFocus)
                    
                    Toggle(NSLocalizedString("override_lock_screen", comment: ""), isOn: $overrideLockScreen)
                    Text(NSLocalizedString("override_lock_screen_help", comment: ""))
                        .font(.caption).foregroundColor(.secondary)
                } header: {
                    Text(NSLocalizedString("automation_header", comment: ""))
                }
                
                Section {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(NSLocalizedString("clear_user_data", comment: ""))
                            Text(NSLocalizedString("reset_property_and_mem", comment: ""))
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Button(NSLocalizedString("clear_all", comment: "")) {
                            showClearDataAlert = true
                        }
                        .alert(isPresented: $showClearDataAlert) {
                            Alert(
                                title: Text(NSLocalizedString("confirm_clear_data", comment: "")),
                                message: Text(NSLocalizedString("clear_all_notice", comment: "")),
                                primaryButton: .destructive(Text(NSLocalizedString("clear_button", comment: "")), action: {
                                    WallpaperPersistence.shared.deleteAllUserData()
                                }),
                                secondaryButton: .cancel()
                            )
                        }
                    }
                } header: {
                    Text(NSLocalizedString("maintenance", comment: ""))
                }
                
                Section {
                    Toggle(NSLocalizedString("launch_at_login", comment: ""), isOn: $launchManager.isLaunchAtLoginEnabled)
                    .toggleStyle(.switch)
                    Toggle(NSLocalizedString("auto_check_updates", comment: ""), isOn: $checkUpdateOnStartup)
                    HStack {
                        Text(String(format: NSLocalizedString("current_version_text", comment: ""), AppInfo.fullVersionString)).foregroundColor(.secondary)
                        Spacer()
                        Button(NSLocalizedString("check_updates_button", comment: "")) { UpdateChecker.shared.checkForUpdates(userInitiated: true) }
                    }
                } header: {
                    Text(NSLocalizedString("updates_header", comment: ""))
                }
                
                Section {
                    HStack {
                        Text(AppInfo.appName)
                        Spacer()
                        Text(NSLocalizedString("license_text", comment: "")).foregroundColor(.secondary)
                    }
                } header: {
                    Text(NSLocalizedString("about_header", comment: ""))
                }
            }
            .formStyle(.grouped)
            .frame(width: 500, height: 600) // Slightly increased height / 略微增加高度
            
            Divider()
            
            HStack {
                Spacer()
                Button(NSLocalizedString("done_button", comment: "")) {
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
        panel.message = NSLocalizedString("choose_storage_folder_message", comment: "")
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                library.setStoragePath(url)
            }
        }
    }
}
