//
//  SidebarView.swift
//  OpenMetalWallpaper
//
//  Created by laobamac on 2026/1/17.
//

import SwiftUI

struct SidebarView: View {
    @Binding var selectedCategory: String?
    
    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedCategory) {
                Section(header: Text(NSLocalizedString("library_header", comment: "Library"))) {
                    Label(NSLocalizedString("installed_label", comment: "Installed"), systemImage: "externaldrive.fill")
                        .tag("installed")
                }
                
                Section(header: Text(NSLocalizedString("discover_header", comment: "Discover"))) {
                    Label(NSLocalizedString("workshop_label", comment: "Workshop"), systemImage: "globe")
                        .tag("workshop")
                }
            }
            .listStyle(.sidebar)
            
            Spacer()
            
            // Footer
            VStack(alignment: .leading, spacing: 10) {
                Divider()
                Link(destination: URL(string: "https://github.com/laobamac/OpenMetalWallpaper")!) {
                    HStack(alignment: .center, spacing: 12) {
                        if let logoImage = NSImage(named: "AppLogo") {
                            Image(nsImage: logoImage).resizable().aspectRatio(contentMode: .fit).frame(width: 40, height: 40)
                        } else {
                            Image(nsImage: NSApp.applicationIconImage).resizable().aspectRatio(contentMode: .fit).frame(width: 40, height: 40)
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            Text("OpenMetalWallpaper").font(.system(size: 13, weight: .bold)).foregroundColor(.primary).lineLimit(1)
                            Text("By laobamac").font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                
                HStack {
                    Text("License: AGPLv3").font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(4).background(Color.gray.opacity(0.2)).cornerRadius(4)
                    Spacer()
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }
}
