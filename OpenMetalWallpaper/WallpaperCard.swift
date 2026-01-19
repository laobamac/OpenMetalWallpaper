/*
 File: WallpaperCard.swift
 Description: Card with Glass Badge and Chinese Type Localization.
 Fixed: Compilation error 'controlBackgroundColor' is not a Material.
*/

import SwiftUI

struct WallpaperCard: View {
    let wallpaper: WallpaperProject
    @State private var isHovering = false
    
    // Type Mapping
    var typeLabel: String {
        let type = wallpaper.type?.lowercased() ?? "video"
        switch type {
        case "video": return "视频"
        case "web": return "网页"
        case "scene": return "场景"
        default: return type.uppercased()
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail area
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.3)
                
                if let thumbPath = wallpaper.thumbnailPath,
                   let nsImage = NSImage(contentsOf: thumbPath) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 120)
                        .clipped()
                } else {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                        .frame(height: 120, alignment: .center)
                        .frame(maxWidth: .infinity)
                }
                
                // Glass Texture Badge
                Text(typeLabel)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                            .cornerRadius(6)
                    )
                    .padding(8)
                    .shadow(radius: 2)
                
                // Play overlay
                if isHovering {
                    Color.black.opacity(0.4)
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .shadow(radius: 4)
                }
            }
            .frame(height: 120)
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(wallpaper.title)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundColor(.primary)
                
                Text(wallpaper.file ?? "未知来源")
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            // [Fixed] Changed invalid .controlBackgroundColor to .popover (Correct Material)
            .background(VisualEffectView(material: .popover, blendingMode: .withinWindow))
        }
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(isHovering ? 0.2 : 0.1), radius: isHovering ? 8 : 4, x: 0, y: 2)
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.spring(response: 0.3), value: isHovering)
        .onHover { hover in isHovering = hover }
    }
}
