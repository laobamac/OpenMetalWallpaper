//
//  ScenePlayerEngine.swift
//  OpenMetalWallpaper
//
//  Created by laobamac on 2026/5/2.
//

import AppKit
import MetalKit

class ScenePlayerEngine: NSObject, WallpaperPlayer {
    private var mtkView: MTKView?
    private var renderer: Renderer?
    private var textureManager: TextureManager?
    private var currentURL: URL?
    private var options: WallpaperOptions?
    private var backgroundView: NSView?

    private var currentVolume: Float = 0.5
    private var currentPlaybackRate: Float = 1.0
    private var currentIsMuted: Bool = false

    func attach(to view: NSView) {
        self.backgroundView = view
        guard let device = MTLCreateSystemDefaultDevice() else {
            Logger.log("无法创建 Metal device")
            return
        }

        let textureManager = TextureManager()
        self.textureManager = textureManager

        let metalView = MTKView(frame: view.bounds)
        metalView.device = device
        metalView.autoresizingMask = [.width, .height]
        metalView.framebufferOnly = false
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.depthStencilPixelFormat = .depth32Float_stencil8
        metalView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        metalView.isPaused = true
        metalView.enableSetNeedsDisplay = false

        self.mtkView = metalView
        view.addSubview(metalView)
    }

    func load(url: URL, options: WallpaperOptions) {
        guard let mtkView = self.mtkView,
              let device = mtkView.device,
              let textureManager = self.textureManager else {
            Logger.log("ScenePlayerEngine: MTKView 或 TextureManager 未初始化")
            return
        }

        self.currentURL = url
        self.options = options

        guard let renderer = Renderer(device: device, view: mtkView, textureManager: textureManager) else {
            Logger.log("无法创建 Renderer")
            return
        }
        self.renderer = renderer
        mtkView.delegate = renderer
        renderer.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)

        let folder = url.deletingLastPathComponent()

        self.currentVolume = options.volume
        self.currentPlaybackRate = options.playbackRate

        Task {
            await renderer.loadScene(folder: folder)
            while !renderer.isReady {
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                mtkView.isPaused = false
                self.applyOptions(options)
            }
        }
    }

    private func applyOptions(_ options: WallpaperOptions) {
        setVolume(options.volume)
        setPlaybackRate(options.playbackRate)
        setMute(false)
        setFrameLimit(options.fpsLimit)
        setBackgroundColor(options.backgroundColor)
        setPostProcessing(brightness: options.brightness, contrast: options.contrast, saturation: options.saturation)
        updateScaling(mode: options.scaleMode, scale: options.videoScale, x: options.xOffset, y: options.yOffset, rotation: options.rotation)
        setInteractive(options.isInteractive)
    }

    func stop() {
        mtkView?.isPaused = true
        mtkView?.delegate = nil
        mtkView?.removeFromSuperview()
        mtkView = nil
        renderer = nil

        Task { [textureManager] in
            await textureManager?.clear()
        }
        textureManager = nil
        currentURL = nil
        backgroundView = nil
    }

    func pause() {
        mtkView?.isPaused = true
    }

    func resume() {
        guard renderer?.isReady == true else { return }
        mtkView?.isPaused = false
    }

    func setVolume(_ volume: Float) {
        currentVolume = volume
        Task { [textureManager, isMuted = currentIsMuted] in
            await textureManager?.setVolume(volume, isMuted: isMuted)
        }
    }

    func setPlaybackRate(_ rate: Float) {
        currentPlaybackRate = rate
        Task { [textureManager] in
            await textureManager?.setPlaybackRate(rate)
        }
    }

    func setMute(_ muted: Bool) {
        currentIsMuted = muted
        Task { [textureManager, volume = currentVolume] in
            await textureManager?.setVolume(volume, isMuted: muted)
        }
    }

    func setFrameLimit(_ fps: Int) {
        let safeFps = max(1, min(fps, 120))
        mtkView?.preferredFramesPerSecond = safeFps
    }

    func setPostProcessing(brightness: Float, contrast: Float, saturation: Float) {
        renderer?.sceneContext.brightness = brightness
        renderer?.sceneContext.contrast = contrast
        renderer?.sceneContext.saturation = saturation
    }

    func setBackgroundColor(_ color: NSColor) {
        guard let mtkView = self.mtkView else { return }
        let calibrated = color.usingColorSpace(.sRGB) ?? color
        mtkView.clearColor = MTLClearColor(
            red: Double(calibrated.redComponent),
            green: Double(calibrated.greenComponent),
            blue: Double(calibrated.blueComponent),
            alpha: Double(calibrated.alphaComponent)
        )
    }

    func updateScaling(mode: WallpaperScaleMode, scale: CGFloat, x: CGFloat, y: CGFloat, rotation: Int) {
        renderer?.sceneContext.scaleMode = mode
        guard let mtkView = self.mtkView, let superview = mtkView.superview else { return }
        let baseFrame = superview.bounds
        let angleRad = CGFloat(rotation % 360) * (.pi / 180.0)
        var targetFrame = baseFrame
        if mode == .custom {
            let scaledWidth = baseFrame.width * scale
            let scaledHeight = baseFrame.height * scale
            targetFrame = CGRect(
                x: (baseFrame.width - scaledWidth) / 2 + x,
                y: (baseFrame.height - scaledHeight) / 2 + y,
                width: scaledWidth,
                height: scaledHeight
            )
        }
        mtkView.frame = targetFrame
        if abs(angleRad) > 0.001 {
            mtkView.layer?.transform = CATransform3DMakeRotation(angleRad, 0, 0, 1)
        } else {
            mtkView.layer?.transform = CATransform3DIdentity
        }
    }

    func snapshot(completion: @escaping (NSImage?) -> Void) {
        guard let mtkView = self.mtkView, let texture = mtkView.currentDrawable?.texture else {
            completion(nil)
            return
        }
        let width = texture.width
        let height = texture.height
        let rowBytes = width * 4
        let totalBytes = rowBytes * height
        var pixels = Data(count: totalBytes)
        pixels.withUnsafeMutableBytes { ptr in
            guard let basePtr = ptr.baseAddress else { return }
            texture.getBytes(basePtr, bytesPerRow: rowBytes, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
        if let provider = CGDataProvider(data: pixels as CFData),
           let cgImage = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: rowBytes, space: colorSpace, bitmapInfo: bitmapInfo, provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) {
            completion(NSImage(cgImage: cgImage, size: NSSize(width: width, height: height)))
        } else {
            completion(nil)
        }
    }

    func updateProperties(_ properties: [String: Any]) {
    }

    func sendAudioData(_ audioArray: [Float]) {
    }

    func setInteractive(_ allowed: Bool) {
    }
}
