/*
 License: AGPLv3
 Author: laobamac
 File: WebPlayerEngine.swift
 Description: WKWebView player with Wallpaper Engine API bridge.
*/

import Cocoa
import WebKit

class WebPlayerEngine: NSObject, WallpaperPlayer, WKNavigationDelegate, WKScriptMessageHandler {
    
    private var webView: WKWebView?
    private weak var containerView: NSView?
    private var currentURL: URL?
    private var currentOptions: WallpaperOptions?
    private var isLoaded: Bool = false
    
    // Audio simulation/injection
    private var audioTimer: Timer?
    
    func attach(to view: NSView) {
        self.containerView = view
    }
    
    func load(url: URL, options: WallpaperOptions) {
        self.currentURL = url
        self.currentOptions = options
        stop()
        
        let config = WKWebViewConfiguration()
        
        // 1. Enable File Access (Crucial for loading images relative to index.html)
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
        
        // 2. Hide scrollbars and setup media playback
        config.preferences.javaScriptEnabled = true
        config.mediaTypesRequiringUserActionForPlayback = []
        
        // 3. Inject Wallpaper Engine Mock API
        // This script intercepts property requests and defines the audio listener hook.
        let bridgeScript = """
        window.wallpaperRegisterAudioListener = function(callback) {
            window.__audioListener = callback;
        };
        window.wallpaperPropertyListener = {
            applyUserProperties: function(props) {
                // Will be called by native code
            }
        };
        """
        let userScript = WKUserScript(source: bridgeScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(userScript)
        config.userContentController.add(self, name: "log") // Debug bridge
        
        let webView = WKWebView(frame: containerView?.bounds ?? .zero, configuration: config)
        webView.navigationDelegate = self
        webView.autoresizingMask = [.width, .height]
        webView.setValue(false, forKey: "drawsBackground") // Transparent background
        webView.enabler = false // Private API to disable drag/drop if possible, or just ignore interactions
        
        // Disable interaction to behave like a wallpaper (unless needed)
        // Usually Wallpaper Engine wallpapers allow mouse interaction (parallax, clicks).
        // If you want to block it: webView.hitTest = { _ in return nil } (Not easy in WKWebView without subclass)
        
        self.containerView?.addSubview(webView)
        self.webView = webView
        
        // Load the file
        // accessURL needs to be the directory to allow relative paths
        let accessURL = url.deletingLastPathComponent()
        webView.loadFileURL(url, allowingReadAccessTo: accessURL)
        
        self.isLoaded = true
        
        // Start Audio Loop if requested (Mocking audio for visualizers)
        // In a real perfect implementation, you would capture system audio here.
        // For this code, we run a timer to prevent visualizers from crashing/looking dead.
        startAudioSimulator()
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Apply initial properties once loaded
        if let props = currentOptions?.userProperties {
            updateProperties(props)
        }
        
        // Apply initial scaling
        if let opts = currentOptions {
            updateScaling(mode: opts.scaleMode, scale: opts.videoScale, x: opts.xOffset, y: opts.yOffset, rotation: opts.rotation)
        }
    }
    
    // MARK: - API Implementation
    
    func updateProperties(_ properties: [String: Any]) {
        guard let webView = webView else { return }
        
        // Transform the simple [Key: Value] dict into Wallpaper Engine's expected format:
        // { "propKey": { "value": theValue }, ... }
        var weProps: [String: [String: Any]] = [:]
        
        for (key, val) in properties {
            // Convert color strings "1 0 0" to "1 0 0" (Web wallpapers usually expect "r g b" string or specific format)
            // If the wallpaper expects normalized "R G B" string (0-1), ensure we pass that.
            // Our UI passes strings or numbers directly.
            weProps[key] = ["value": val]
        }
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: weProps, options: []),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            let js = """
            if (window.wallpaperPropertyListener && window.wallpaperPropertyListener.applyUserProperties) {
                window.wallpaperPropertyListener.applyUserProperties(\(jsonString));
            }
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }
    
    func sendAudioData(_ audioArray: [Float]) {
        // Wallpaper Engine expects an array of 128 floats (64 left, 64 right) usually, or just 128 spectrum bins.
        // JS: window.__audioListener(array)
        guard let webView = webView else { return }
        
        // Optimize: Don't serialize generic JSON every frame for audio, construct string manually for speed
        let strValues = audioArray.map { String(format: "%.3f", $0) }.joined(separator: ",")
        let js = "if(window.__audioListener) { window.__audioListener([\(strValues)]); }"
        
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
    
    // MARK: - Simulation / Controls
    
    func stop() {
        audioTimer?.invalidate()
        audioTimer = nil
        webView?.stopLoading()
        webView?.configuration.userContentController.removeAllUserScripts()
        webView?.removeFromSuperview()
        webView = nil
        isLoaded = false
    }
    
    func pause() {
        // Web wallpapers can be paused by stopping the audio loop or injecting a pause event
        // Wallpaper Engine API: window.wallpaperPropertyListener.setPaused(true) (Unofficial)
        // Usually, just stopping `requestAnimationFrame` via standard browser behavior when hidden works,
        // but here we are on desktop.
        // We will pause the audio feed, which stops visualizers.
        audioTimer?.invalidate()
        audioTimer = nil
        // Inject pause flag if wallpaper supports it
        webView?.evaluateJavaScript("if(window.wallpaperPropertyListener.setPaused) { window.wallpaperPropertyListener.setPaused(true); }", completionHandler: nil)
    }
    
    func resume() {
        startAudioSimulator()
        webView?.evaluateJavaScript("if(window.wallpaperPropertyListener.setPaused) { window.wallpaperPropertyListener.setPaused(false); }", completionHandler: nil)
    }
    
    func setVolume(_ volume: Float) {
        // Web Audio API volume control if applicable, or generic video tag
        let script = "document.querySelectorAll('video, audio').forEach(e => e.volume = \(volume));"
        webView?.evaluateJavaScript(script, completionHandler: nil)
    }
    
    func setPlaybackRate(_ rate: Float) {
        let script = "document.querySelectorAll('video, audio').forEach(e => e.playbackRate = \(rate));"
        webView?.evaluateJavaScript(script, completionHandler: nil)
    }
    
    func setMute(_ muted: Bool) {
        let script = "document.querySelectorAll('video, audio').forEach(e => e.muted = \(muted));"
        webView?.evaluateJavaScript(script, completionHandler: nil)
    }
    
    func setFrameLimit(_ fps: Int) {
        // Cannot easily limit FPS in WKWebView without blocking main thread.
        // Browsers handle this via vsync.
    }
    
    func setPostProcessing(brightness: Float, contrast: Float, saturation: Float) {
        // Inject CSS filters on the body
        // brightness(1) contrast(1) saturate(1)
        // Note: brightness is -0.5 to 0.5 in our app, CSS is 0.5 to 1.5 usually?
        // App logic: 0 is default. CSS default is 100% (1.0).
        // Let's map: 0 -> 100%, 0.5 -> 150%, -0.5 -> 50%
        let bVal = (brightness + 1.0) * 100
        let cVal = contrast * 100
        let sVal = saturation * 100
        
        let css = "brightness(\(bVal)%) contrast(\(cVal)%) saturate(\(sVal)%)"
        let script = "document.body.style.filter = '\(css)';"
        webView?.evaluateJavaScript(script, completionHandler: nil)
    }
    
    func setBackgroundColor(_ color: NSColor) {
        // Usually web wallpapers cover everything, but if transparent:
        self.containerView?.layer?.backgroundColor = color.cgColor
    }
    
    func updateScaling(mode: WallpaperScaleMode, scale: CGFloat, x: CGFloat, y: CGFloat, rotation: Int) {
        // We can apply CSS transform to the body
        guard let webView = webView else { return }
        
        // CSS Transform
        var transform = ""
        if rotation != 0 { transform += "rotate(\(rotation)deg) " }
        if mode == .custom {
            transform += "translate(\(x)px, \(y)px) scale(\(scale))"
        } else if mode == .fill {
            // CSS cover is default for body usually, but we can force it
             webView.evaluateJavaScript("document.body.style.backgroundSize = 'cover';", completionHandler: nil)
        } else if mode == .fit {
             webView.evaluateJavaScript("document.body.style.backgroundSize = 'contain';", completionHandler: nil)
        }
        
        if !transform.isEmpty {
            webView.evaluateJavaScript("document.body.style.transform = '\(transform)'; document.body.style.transformOrigin = 'center center';", completionHandler: nil)
        } else {
             webView.evaluateJavaScript("document.body.style.transform = '';", completionHandler: nil)
        }
    }
    
    func snapshot(completion: @escaping (NSImage?) -> Void) {
        guard let webView = webView else { completion(nil); return }
        let config = WKSnapshotConfiguration()
        config.rect = webView.bounds
        webView.takeSnapshot(with: config) { image, error in
            completion(image)
        }
    }
    
    // MARK: - Internals
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        print("WebLog: \(message.body)")
    }
    
    private func startAudioSimulator() {
        audioTimer?.invalidate()
        // 30 FPS audio update
        audioTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            // Generate dummy audio spectrum (randomized to look alive)
            // 128 bins. 0.0 to 1.0
            var data = [Float](repeating: 0, count: 128)
            for i in 0..<128 {
                // Simulating some bass (lower indexes) and noise
                let base = Float(i) / 128.0
                let val = Float.random(in: 0...0.5) * (1.0 - base)
                data[i] = val
            }
            self.sendAudioData(data)
        }
    }
}

// Helper to disable drag drop interactions on WKWebView if needed
extension WKWebView {
    var enabler: Bool {
        get { return false }
        set {
             // Private API tricks or simply use specific overlapping view to block input if desired
        }
    }
}
