/*
 License: AGPLv3
 Author: laobamac
 File: WallpaperProtocols.swift
 Description: Interfaces updated with Rotation support.
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
    
    func setBackgroundColor(_ color: NSColor)
    
    func updateScaling(mode: WallpaperScaleMode, scale: CGFloat, x: CGFloat, y: CGFloat, rotation: Int)
    
    func snapshot(completion: @escaping (NSImage?) -> Void)
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
    var rotation: Int // 0, 90, 180, 270
}
