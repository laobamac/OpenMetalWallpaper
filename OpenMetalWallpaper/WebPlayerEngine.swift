/*
 License: AGPLv3
 Author: laobamac
 File: WebPlayerEngine.swift
 Description: Web Engine with Safe Color Conversion & Focus Safety.
*/

import Cocoa
import WebKit
import UniformTypeIdentifiers

class LocalSchemeHandler: NSObject, WKURLSchemeHandler {
    private let rootFolder: URL
    init(rootFolder: URL) { self.rootFolder = rootFolder }
    
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else { return }
        var pathString = url.path
        if pathString.hasPrefix("/") { pathString = String(pathString.dropFirst()) }
        guard let decodedPath = pathString.removingPercentEncoding else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        let localURL = rootFolder.appendingPathComponent(decodedPath)
        do {
            let data = try Data(contentsOf: localURL)
            let ext = localURL.pathExtension.lowercased()
            let mime = self.mimeType(for: ext)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
                "Content-Type": mime,
                "Access-Control-Allow-Origin": "*",
                "Cache-Control": "no-cache"
            ])!
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didFinish()
        }
    }
    
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
    
    private func mimeType(for `extension`: String) -> String {
        switch `extension` {
        case "html", "htm": return "text/html"
        case "css": return "text/css"
        case "js": return "application/javascript"
        case "json": return "application/json"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "svg": return "image/svg+xml"
        case "mp3": return "audio/mpeg"
        case "mp4": return "video/mp4"
        case "webm": return "video/webm"
        default:
            if let type = UTType(filenameExtension: `extension`)?.preferredMIMEType { return type }
            return "application/octet-stream"
        }
    }
}

class WebPlayerEngine: NSObject, WallpaperPlayer, WKNavigationDelegate, WKUIDelegate {
    private var webView: WKWebView?
    private var pauseOverlay: NSImageView?
    private weak var containerView: NSView?
    private var options: WallpaperOptions?
    private var schemeHandler: LocalSchemeHandler?
    private var currentURL: URL?
    private var isPausedState: Bool = false
    
    func attach(to view: NSView) {
        self.containerView = view
    }
    
    private func requestFocusRestoration() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name("omw_restore_focus"), object: nil)
        }
    }
    
    func load(url: URL, options: WallpaperOptions) {
        self.options = options
        self.currentURL = url
        self.isPausedState = false
        stop()
        cleanupTempImage(for: url)
        setupWebView(url: url)
    }
    
    private func setupWebView(url: URL) {
            guard let view = containerView else { return }
            let rootDir = url.deletingLastPathComponent()
            let config = WKWebViewConfiguration()
            let handler = LocalSchemeHandler(rootFolder: rootDir)
            self.schemeHandler = handler
            config.setURLSchemeHandler(handler, forURLScheme: "omw-local")
            config.mediaTypesRequiringUserActionForPlayback = []
            config.preferences.setValue(true, forKey: "developerExtrasEnabled")
            
            let css = "html, body { width: 100%; height: 100%; margin: 0; padding: 0; overflow: hidden; } ::-webkit-scrollbar { display: none; }"
            
            let wallpaperEngineMock = """
            var style = document.createElement('style'); style.innerHTML = `\(css)`; document.head.appendChild(style);
            var meta = document.createElement('meta'); meta.name = "viewport"; meta.content = "width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no"; document.head.appendChild(meta);
            setTimeout(function() {
                if (window.wallpaperPropertyListener && window.wallpaperPropertyListener.applyUserProperties) {
                    var mockProps = {}; 
                    window.wallpaperPropertyListener.applyUserProperties(mockProps);
                } else {
                    if (typeof addImage === 'function') { addImage(); }
                }
            }, 500);
            """
            config.userContentController.addUserScript(WKUserScript(source: wallpaperEngineMock, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
            
            let wv = WKWebView(frame: view.bounds, configuration: config)
            wv.autoresizingMask = [.width, .height]
            wv.allowsMagnification = false
            wv.navigationDelegate = self
            wv.uiDelegate = self
            
            if let scrollView = view.findFirstScrollView() {
                scrollView.hasVerticalScroller = false; scrollView.hasHorizontalScroller = false
                scrollView.verticalScrollElasticity = .none; scrollView.horizontalScrollElasticity = .none
            }
            
            if let overlay = pauseOverlay { view.addSubview(wv, positioned: .below, relativeTo: overlay) } else { view.addSubview(wv) }
            self.webView = wv
            
            let entryFileName = url.lastPathComponent
            if let encodedName = entryFileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
               let virtualURL = URL(string: "omw-local://host/\(encodedName)") {
                wv.load(URLRequest(url: virtualURL))
            }
            
            requestFocusRestoration()
        }
    
    func pause() {
        guard !isPausedState, let wv = webView, let url = currentURL else { return }
        
        let config = WKSnapshotConfiguration()
        config.rect = wv.bounds
        
        wv.takeSnapshot(with: config) { [weak self] image, error in
            guard let self = self, let snapshot = image else { return }
            self.saveTempImage(snapshot, for: url)
            
            let overlay = NSImageView(frame: wv.frame)
            overlay.image = snapshot
            overlay.imageScaling = .scaleAxesIndependently
            overlay.autoresizingMask = [.width, .height]
            
            self.containerView?.addSubview(overlay)
            self.pauseOverlay = overlay
            
            self.webView?.stopLoading()
            self.webView?.removeFromSuperview()
            self.webView = nil
            self.schemeHandler = nil
            self.isPausedState = true
            
            self.requestFocusRestoration()
        }
    }
    
    func resume() {
        guard isPausedState, let url = currentURL else { return }
        setupWebView(url: url)
        self.isPausedState = false
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let color = options?.backgroundColor { setBackgroundColor(color) }
        if let rot = options?.rotation {
            updateScaling(mode: .fill, scale: 1.0, x: 0, y: 0, rotation: rot)
        }
        if let vol = options?.volume { setVolume(vol) }
        
        if let overlay = self.pauseOverlay {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                overlay.removeFromSuperview()
                self.pauseOverlay = nil
                if let url = self.currentURL { self.cleanupTempImage(for: url) }
            }
        }
    }

    func snapshot(completion: @escaping (NSImage?) -> Void) {
        guard let wv = webView else { completion(nil); return }
        let config = WKSnapshotConfiguration()
        config.rect = wv.bounds
        wv.takeSnapshot(with: config) { image, _ in
            completion(image)
        }
    }
    
    private func getTempPath(for url: URL) -> URL {
        return FileManager.default.temporaryDirectory.appendingPathComponent("omw_pause_\(url.hashValue).png")
    }
    
    private func saveTempImage(_ image: NSImage, for url: URL) {
        if let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            try? pngData.write(to: getTempPath(for: url))
        }
    }
    
    private func cleanupTempImage(for url: URL) {
        try? FileManager.default.removeItem(at: getTempPath(for: url))
    }
    
    func stop() {
        if let wv = webView {
            wv.stopLoading()
            wv.configuration.userContentController.removeAllUserScripts()
            wv.removeFromSuperview()
        }
        webView = nil
        schemeHandler = nil
        
        pauseOverlay?.removeFromSuperview()
        pauseOverlay = nil
        
        if let url = currentURL { cleanupTempImage(for: url) }
        isPausedState = false
    }
    
    func setBackgroundColor(_ color: NSColor) {
        self.options?.backgroundColor = color
            
        webView?.layer?.backgroundColor = color.cgColor
        guard let rgbColor = color.usingColorSpace(.sRGB) else { return }
        let r = String(format: "%.3f", rgbColor.redComponent)
        let g = String(format: "%.3f", rgbColor.greenComponent)
        let b = String(format: "%.3f", rgbColor.blueComponent)
        let js = "if(window.wallpaperPropertyListener&&window.wallpaperPropertyListener.applyUserProperties){var props={schemecolor:{value:'\(r) \(g) \(b)'}};window.wallpaperPropertyListener.applyUserProperties(props);}"
            webView?.evaluateJavaScript(js, completionHandler: nil)
    }
        
    func setVolume(_ volume: Float) {
        self.options?.volume = volume
            
        let js = "document.querySelectorAll('video, audio').forEach(el => el.volume = \(volume));"
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }
        
    func setMute(_ muted: Bool) {}
    func setPlaybackRate(_ rate: Float) {}
        
    func updateScaling(mode: WallpaperScaleMode, scale: CGFloat, x: CGFloat, y: CGFloat, rotation: Int) {

        self.options?.rotation = rotation
            
        var js = """
        document.body.style.transform = 'rotate(\(rotation)deg)';
        document.body.style.transformOrigin = 'center center';
        """
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }
}
