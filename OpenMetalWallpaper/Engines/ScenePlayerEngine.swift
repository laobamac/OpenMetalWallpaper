//
//  ScenePlayerEngine.swift
//  OpenMetalWallpaper
//
//  Created by laobamac on 2026/1/17.
//

import Cocoa
import MetalKit
import SwiftUI
import CoreImage
import CoreGraphics

class ScenePlayerEngine: NSObject, WallpaperPlayer {
    
    private var mtkView: MTKView?
    private var renderer: Renderer?
    private weak var containerView: NSView?
    private var currentOptions: WallpaperOptions?
    
    // Audio is not currently supported in this Renderer implementation
    
    func attach(to view: NSView) {
        self.containerView = view
        
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("ScenePlayerEngine: Failed to create Metal device")
            return
        }
        
        let mtkView = MTKView(frame: view.bounds, device: device)
        mtkView.autoresizingMask = [.width, .height]
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.depthStencilPixelFormat = .depth32Float_stencil8
        mtkView.preferredFramesPerSecond = 60
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false
        mtkView.framebufferOnly = false
        
        // Initialize Renderer
        if let renderer = Renderer(device: device) {
            self.renderer = renderer
            mtkView.delegate = renderer
            print("ScenePlayerEngine: Renderer attached successfully")
        } else {
            print("ScenePlayerEngine: Failed to initialize Renderer")
        }
        
        view.addSubview(mtkView)
        self.mtkView = mtkView
    }
    
    func load(url: URL, options: WallpaperOptions) {
        self.currentOptions = options
        print("ScenePlayerEngine: Loading URL: \(url.path)")
        
        // Apply initial settings
        setFrameLimit(options.fpsLimit)
        setPostProcessing(brightness: options.brightness, contrast: options.contrast, saturation: options.saturation)
        updateScaling(mode: options.scaleMode, scale: options.videoScale, x: options.xOffset, y: options.yOffset, rotation: options.rotation)

        let folderURL = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        
        print("ScenePlayerEngine: Corrected Folder URL: \(folderURL.path)")
        renderer?.loadScene(folder: folderURL)
    }
    
    func stop() {
        mtkView?.isPaused = true
        mtkView?.removeFromSuperview()
        mtkView = nil
        renderer = nil
    }
    
    func pause() {
        mtkView?.isPaused = true
    }
    
    func resume() {
        mtkView?.isPaused = false
    }
    
    func setVolume(_ volume: Float) {
        // Audio not supported in current Renderer
    }
    
    func setPlaybackRate(_ rate: Float) {
        renderer?.timeScale = rate
    }
    
    func setMute(_ muted: Bool) {
        // Audio not supported
    }
    
    func setFrameLimit(_ fps: Int) {
        mtkView?.preferredFramesPerSecond = fps
    }
    
    func setPostProcessing(brightness: Float, contrast: Float, saturation: Float) {
        renderer?.setPostProcessing(brightness: brightness, contrast: contrast, saturation: saturation)
    }
    
    func setBackgroundColor(_ color: NSColor) {
        guard let rgb = color.usingColorSpace(.sRGB) else { return }
        mtkView?.clearColor = MTLClearColor(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent, alpha: 1.0)
    }
    
    func updateScaling(mode: WallpaperScaleMode, scale: CGFloat, x: CGFloat, y: CGFloat, rotation: Int) {
        renderer?.updateTransform(scale: Float(scale), offset: SIMD2<Float>(Float(x), Float(y)), rotation: Float(rotation))
    }
    
    func snapshot(completion: @escaping (NSImage?) -> Void) {
        DispatchQueue.main.async {
            guard let windowID = self.mtkView?.window?.windowNumber else {
                print("Snapshot Failed: Window not attached.")
                completion(nil)
                return
            }
            
            let imageRef = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(windowID), [.boundsIgnoreFraming, .nominalResolution])
            
            if let cgImage = imageRef {
                let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                completion(nsImage)
            } else {
                print("Snapshot Failed: CGWindowListCreateImage returned null.")
                completion(nil)
            }
        }
    }
    
    func updateProperties(_ properties: [String : Any]) {
        // Pass to renderer if it supports property updates
    }
    
    func sendAudioData(_ audioArray: [Float]) {
        // Pass to renderer for audio reactive shaders
    }
    
    func setInteractive(_ allowed: Bool) {
        // Handle interaction state
    }
}
