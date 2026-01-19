/*
 File: WebPlayerEngine.swift
 Description: Web Player with Silent-Audio support and Error Suppression.
*/

import Cocoa
import WebKit
import AVFoundation

class WebPlayerEngine: NSObject, WallpaperPlayer, WKNavigationDelegate, WKScriptMessageHandler {
    
    private var webView: WKWebView?
    private weak var containerView: NSView?
    private var currentURL: URL?
    private var currentOptions: WallpaperOptions?
    private var isLoaded: Bool = false
    
    // Audio
    private var audioAnalyzer: AudioSpectrumAnalyzer?
    private var audioSimulatorTimer: Timer?
    private var lastAudioUpdate: TimeInterval = 0
    private var isRealAudioActive: Bool = false
    
    func attach(to view: NSView) {
        self.containerView = view
        NotificationCenter.default.addObserver(self, selector: #selector(restartAudio), name: Notification.Name("omw_audioDeviceChanged"), object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        stop()
    }
    
    func load(url: URL, options: WallpaperOptions) {
        self.currentURL = url
        self.currentOptions = options
        stop()
        
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
        config.preferences.javaScriptEnabled = true
        config.mediaTypesRequiringUserActionForPlayback = []
        
        // MARK: - Smart Bridge (Suppress Errors)
        let bridgeScript = """
        window.wallpaperRegisterAudioListener = function(callback) {
            window.__audioListener = callback;
        };
        window.wallpaperPropertyListener = {
            applyUserProperties: function(props) {},
            setPaused: function(p) {}
        };
        // Polling for readiness
        var _omw_checkInterval = setInterval(function() {
            if (window.wallpaperPropertyListener && window.wallpaperPropertyListener.applyUserProperties) {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.omw_internal) {
                    window.webkit.messageHandlers.omw_internal.postMessage("READY");
                }
                clearInterval(_omw_checkInterval);
            }
        }, 100);
        """
        
        let userScript = WKUserScript(source: bridgeScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(userScript)
        config.userContentController.add(self, name: "omw_internal")
        config.userContentController.add(self, name: "log")
        
        let webView = WKWebView(frame: containerView?.bounds ?? .zero, configuration: config)
        webView.navigationDelegate = self
        webView.autoresizingMask = [.width, .height]
        webView.setValue(false, forKey: "drawsBackground")
        webView.enabler = false
        
        self.containerView?.addSubview(webView)
        self.webView = webView
        
        let accessURL = url.deletingLastPathComponent()
        webView.loadFileURL(url, allowingReadAccessTo: accessURL)
        
        self.isLoaded = false // Will set true in didFinish
        startAudioSystem()
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        self.isLoaded = true
        sendInitialState()
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "omw_internal", let body = message.body as? String, body == "READY" {
            // Wallpaper is ready for properties
            sendInitialState()
        }
    }
    
    // Safe JS Evaluation to prevent Console Spam
    private func evaluateJS(_ script: String) {
        guard let webView = webView, isLoaded else { return }
        // We do a fire-and-forget approach, but wrapped in native check
        // Ideally we would wrap the JS in try-catch blocks too if the internal engine is flaky
        webView.evaluateJavaScript(script, completionHandler: nil)
    }
    
    private func sendInitialState() {
        guard let options = currentOptions else { return }
        setVolume(options.volume)
        setPlaybackRate(options.playbackRate)
        setMute(options.volume <= 0.001)
        if !options.userProperties.isEmpty { updateProperties(options.userProperties) }
        updateScaling(mode: options.scaleMode, scale: options.videoScale, x: options.xOffset, y: options.yOffset, rotation: options.rotation)
        setPostProcessing(brightness: options.brightness, contrast: options.contrast, saturation: options.saturation)
    }
    
    // MARK: - Audio
    
    @objc private func restartAudio() {
        startAudioSystem()
    }
    
    private func startAudioSystem() {
        audioAnalyzer?.stop()
        audioSimulatorTimer?.invalidate()
        
        audioAnalyzer = AudioSpectrumAnalyzer()
        audioAnalyzer?.onSpectrumData = { [weak self] (data, isSilence) in
            guard let self = self else { return }
            
            // 重要修复：
            // 如果收到了数据（哪怕是全0的静音），也视为真实音频源正在工作。
            // 只有当长时间没有收到回调时，才启用模拟器。
            self.lastAudioUpdate = Date().timeIntervalSince1970
            self.isRealAudioActive = true
            
            self.sendAudioData(data)
        }
        
        let deviceID = UserDefaults.standard.string(forKey: "omw_audioDeviceID")
        audioAnalyzer?.start(deviceID: deviceID)
        
        // Watchdog: Only run simulator if we haven't heard from Real Audio for 1 second.
        // This prevents the simulator from fighting with BlackHole's silence.
        audioSimulatorTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let now = Date().timeIntervalSince1970
            if now - self.lastAudioUpdate > 1.0 {
                self.isRealAudioActive = false
                self.runSimulatorFrame()
            }
        }
    }
    
    private func runSimulatorFrame() {
        // Only simulate if real audio is dead/permission denied
        var data = [Float](repeating: 0, count: 128)
        for i in 0..<128 {
            let base = Float(i) / 128.0
            let val = Float.random(in: 0...0.2) * (1.0 - base)
            data[i] = val
        }
        self.sendAudioData(data)
    }
    
    func sendAudioData(_ audioArray: [Float]) {
        let strValues = audioArray.map { String(format: "%.3f", $0) }.joined(separator: ",")
        // Wrap in try-catch to suppress console errors if window.__audioListener is missing
        let js = "try { if(window.__audioListener) { window.__audioListener([\(strValues)]); } } catch(e) {}"
        evaluateJS(js)
    }
    
    // MARK: - Controls
    
    func updateProperties(_ properties: [String: Any]) {
        guard !properties.isEmpty else { return }
        var weProps: [String: [String: Any]] = [:]
        for (key, val) in properties { weProps[key] = ["value": val] }
        if let jsonData = try? JSONSerialization.data(withJSONObject: weProps, options: []),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            let js = "try { if (window.wallpaperPropertyListener && window.wallpaperPropertyListener.applyUserProperties) { window.wallpaperPropertyListener.applyUserProperties(\(jsonString)); } } catch(e) {}"
            evaluateJS(js)
        }
    }
    
    func stop() {
        audioAnalyzer?.stop()
        audioSimulatorTimer?.invalidate()
        webView?.stopLoading()
        webView?.configuration.userContentController.removeAllUserScripts()
        webView?.removeFromSuperview()
        webView = nil
    }
    
    func pause() {
        audioAnalyzer?.stop()
        audioSimulatorTimer?.invalidate()
        evaluateJS("try { if(window.wallpaperPropertyListener.setPaused) { window.wallpaperPropertyListener.setPaused(true); } } catch(e) {}")
    }
    
    func resume() {
        startAudioSystem()
        evaluateJS("try { if(window.wallpaperPropertyListener.setPaused) { window.wallpaperPropertyListener.setPaused(false); } } catch(e) {}")
    }
    
    func setVolume(_ volume: Float) {
        evaluateJS("document.querySelectorAll('video, audio').forEach(e => e.volume = \(volume));")
    }
    func setPlaybackRate(_ rate: Float) {
        evaluateJS("document.querySelectorAll('video, audio').forEach(e => e.playbackRate = \(rate));")
    }
    func setMute(_ muted: Bool) {
        evaluateJS("document.querySelectorAll('video, audio').forEach(e => e.muted = \(muted));")
    }
    func setFrameLimit(_ fps: Int) {}
    func setPostProcessing(brightness: Float, contrast: Float, saturation: Float) {
        let css = "brightness(\((brightness + 1.0) * 100)%) contrast(\(contrast * 100)%) saturate(\(saturation * 100)%)"
        evaluateJS("document.body.style.filter = '\(css)';")
    }
    func setBackgroundColor(_ color: NSColor) { self.containerView?.layer?.backgroundColor = color.cgColor }
    func updateScaling(mode: WallpaperScaleMode, scale: CGFloat, x: CGFloat, y: CGFloat, rotation: Int) {
        var transform = ""
        if rotation != 0 { transform += "rotate(\(rotation)deg) " }
        if mode == .custom { transform += "translate(\(x)px, \(y)px) scale(\(scale))" }
        let bgSize = mode == .fill ? "cover" : (mode == .fit ? "contain" : "auto")
        evaluateJS("document.body.style.backgroundSize = '\(bgSize)'; document.body.style.transform = '\(transform)'; document.body.style.transformOrigin = 'center center';")
    }
    func snapshot(completion: @escaping (NSImage?) -> Void) {
        guard let webView = webView else { completion(nil); return }
        let config = WKSnapshotConfiguration()
        config.rect = webView.bounds
        webView.takeSnapshot(with: config) { image, error in completion(image) }
    }
}

extension WKWebView {
    var enabler: Bool { get { return false } set { } }
}
