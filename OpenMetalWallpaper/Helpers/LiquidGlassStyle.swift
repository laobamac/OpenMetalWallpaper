//
//  LiquidGlassStyle.swift
//  OpenMetalWallpaper
//
//  Created by laobamac on 2026/1/17.
//

import SwiftUI

func isMacOSTahoeOrLater() -> Bool {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    return version.majorVersion >= 26
}

struct LiquidGlassModifier: ViewModifier {
    var padding: CGFloat = 10
    
    func body(content: Content) -> some View {
        if isMacOSTahoeOrLater() {
            content
                .background(
                    ZStack {
                        // Underlying Gaussian blur / 底层高斯模糊
                        VisualEffectView(material: .headerView, blendingMode: .behindWindow)
                            .opacity(0.8)
                        
                        // Liquid gloss effect / 液态光泽
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.05),
                                Color.blue.opacity(0.02),
                                Color.white.opacity(0.05)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                )
                // Glass edge highlight / 玻璃边缘高光
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            LinearGradient(
                                gradient: Gradient(colors: [.white.opacity(0.4), .white.opacity(0.1)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5) // Floating shadow / 悬浮阴影
        } else {
            // macOS 14-15: Keep native style, no extra processing or simple background only / macOS 14-15: 保持原生风格，不做额外处理或仅做简单背景
            content
                .background(Color(nsColor: .controlBackgroundColor))
        }
    }
}

// Helper: SwiftUI uses NSVisualEffectView / 辅助：SwiftUI 使用 NSVisualEffectView
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

extension View {
    func liquidGlassStyle() -> some View {
        self.modifier(LiquidGlassModifier())
    }
}
