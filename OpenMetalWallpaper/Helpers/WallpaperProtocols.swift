//
//  WallpaperProtocols.swift
//  OpenMetalWallpaper
//
//  Created by laobamac on 2026/1/17.
//

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
    
    func setPostProcessing(brightness: Float, contrast: Float, saturation: Float)
    
    func setBackgroundColor(_ color: NSColor)
    
    func updateScaling(mode: WallpaperScaleMode, scale: CGFloat, x: CGFloat, y: CGFloat, rotation: Int)
    
    func snapshot(completion: @escaping (NSImage?) -> Void)
    
    func updateProperties(_ properties: [String: Any])
    func sendAudioData(_ audioArray: [Float])
    
    func setInteractive(_ allowed: Bool)
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
    
    var isInteractive: Bool
    var userProperties: [String: Any] = [:]
}
