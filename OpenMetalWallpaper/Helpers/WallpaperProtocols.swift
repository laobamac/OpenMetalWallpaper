/*
 License: AGPLv3
 Author: laobamac
 File: WallpaperProtocols.swift
 Description: Interfaces updated for Web Properties & Audio & Interaction.
*/

import Cocoa
import AVFoundation

protocol WallpaperPlayer: NSObjectProtocol {
    func attach(to view: NSView)
    func load(url: URL, options: WallpaperOptions)
    func stop()
    func pause()
    func resume()
    
    func setVolume(_ volume: Float)
    func setPlaybackRate(_ rate: Float)
    func setMute(_ muted: Bool)
    
    func setFrameLimit(_ fps: Int)
    
    // Video Post-Processing (Web wallpaper handles this internally via properties usually, but keeping interface)
    func setPostProcessing(brightness: Float, contrast: Float, saturation: Float)
    
    func setBackgroundColor(_ color: NSColor)
    
    func updateScaling(mode: WallpaperScaleMode, scale: CGFloat, x: CGFloat, y: CGFloat, rotation: Int)
    
    func snapshot(completion: @escaping (NSImage?) -> Void)
    
    // Send generic properties (for Web wallpapers)
    func updateProperties(_ properties: [String: Any])
    
    // Send audio data (for Web visualizers)
    func sendAudioData(_ audioArray: [Float])
}

struct WallpaperOptions {
    let isMemoryMode: Bool
    let isLooping: Bool
    var volume: Float
    var playbackRate: Float
    var scaleMode: WallpaperScaleMode
    var videoScale: CGFloat
    var xOffset: CGFloat
    var yOffset: CGFloat
    var backgroundColor: NSColor
    var rotation: Int
    var fpsLimit: Int
    
    var brightness: Float
    var contrast: Float
    var saturation: Float
    
    // Web Interaction
    var isInteractive: Bool
    
    // Initial user properties from JSON
    var userProperties: [String: Any] = [:]
}
