/*
 License: AGPLv3
 Author: laobamac
 File: WallpaperCard.swift
 Description: View component
*/

import SwiftUI

struct WallpaperCard: View {
    let wallpaper: WallpaperProject
    @State private var isHovering = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail area / 缩略图区域
            ZStack {
                Color.black.opacity(0.3)
                
                if let thumbPath = wallpaper.thumbnailPath,
                   let nsImage = NSImage(contentsOf: thumbPath) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 120)
                        .clipped()
                } else {
                    Image(systemName: "film")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                }
                
                // Play icon overlay on hover / 播放图标悬浮
                if isHovering {
                    Color.black.opacity(0.4)
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white)
                }
            }
            .frame(height: 120)
            
            // Information area / 信息区域
            VStack(alignment: .leading, spacing: 4) {
                Text(wallpaper.title)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundColor(.primary)
                
                Text(wallpaper.file ?? NSLocalizedString("unknown_source", comment: ""))
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isHovering ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .shadow(radius: isHovering ? 4 : 2)
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.spring(response: 0.3), value: isHovering)
        .onHover { hover in
            isHovering = hover
        }
    }
}
