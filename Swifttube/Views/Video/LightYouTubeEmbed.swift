
/*
 Overview / Genel Bakış
 EN: Lightweight, WKWebView-based YouTube embed with minimal UI and a small controller surface.
 TR: Minimal arayüzlü, küçük bir denetleyici yüzeyine sahip WKWebView tabanlı hafif YouTube gömme bileşeni.
*/

// EN: SwiftUI + WebKit interop for a custom, controllable YT embed. TR: Özelleştirilebilir YT gömme için SwiftUI + WebKit birlikte çalışması.
import SwiftUI
import WebKit

// A WKWebView that forwards scroll events to its next responders so that
// the surrounding SwiftUI/NSScrollView keeps scrolling even when the mouse is
// over the player (YouTube often captures wheel events for volume).
// EN: WebView subclass forwarding vertical scroll to parent; can suppress context menu. TR: Dikey kaydırmayı ebeveyne ileten, bağlam menüsünü bastırabilen WebView alt sınıfı.
final class PassthroughWKWebView: WKWebView {
    // When true, suppress the native right-click context menu entirely
    var disableContextMenu: Bool = false

    override func scrollWheel(with event: NSEvent) {
        // Forward vertical scroll to parent scroll views to allow page scrolling.
        // Keep horizontal gestures (e.g., timeline scrubbing) for the player.
        let absX = abs(event.scrollingDeltaX)
        let absY = abs(event.scrollingDeltaY)
        if absY >= absX {
            // Pass to next responders (SwiftUI scroll view) instead of consuming it here.
            nextResponder?.scrollWheel(with: event)
            return
        }
        super.scrollWheel(with: event)
    }

    override func keyDown(with event: NSEvent) {
        // Left/Right arrow -> seek -/+ 5s like YouTube default
        guard let chars = event.charactersIgnoringModifiers, let first = chars.unicodeScalars.first else {
            super.keyDown(with: event); return
        }
        let left: UInt32 = 0xF702 // NSLeftArrowFunctionKey
        let right: UInt32 = 0xF703 // NSRightArrowFunctionKey
        if first.value == left || first.value == right {
            let delta = first.value == right ? 5.0 : -5.0
            evaluateJavaScript("window.__seekRelative && window.__seekRelative(\(delta));", completionHandler: nil)
            return
        }
        super.keyDown(with: event)
    }

    // Suppress context menu when requested (macOS 13+ has menu(for event:), older uses NSView's menu creation)
    override func menu(for event: NSEvent) -> NSMenu? {
        if disableContextMenu { return nil }
        return super.menu(for: event)
    }

    // Additionally swallow secondary-click sources so the web content (iframe/video) never sees them.
    override func rightMouseDown(with event: NSEvent) {
        if disableContextMenu {
            // Forward to parent so SwiftUI .contextMenu can handle it
            nextResponder?.rightMouseDown(with: event)
            return
        }
        super.rightMouseDown(with: event)
    }
    override func otherMouseDown(with event: NSEvent) {
        // Middle-click often maps to buttonNumber 2; treat as context if disabled
        if disableContextMenu, event.buttonNumber == 2 {
            nextResponder?.rightMouseDown(with: event)
            return
        }
        super.otherMouseDown(with: event)
    }
    override func mouseDown(with event: NSEvent) {
        // Control-click is a common alternate for context menu
        if disableContextMenu, event.modifierFlags.contains(.control) {
            // Promote to a context click for parent handlers
            nextResponder?.rightMouseDown(with: event)
            return
        }
        super.mouseDown(with: event)
    }
}

// Lightweight YouTube embed without YouTubePlayerKit to control WKWebView lifecycle.
@MainActor
// EN: Thin controller around the player/fallback iframe offering play/pause/seek/time. TR: Oynatıcı/fallback iframe etrafında oynat/duraklat/sar/zaman sunan ince denetleyici.
final class LightYouTubeController: ObservableObject {
    fileprivate weak var webView: WKWebView?
    // Dynamic changes disabled – user must restart app for new appearance settings.
    fileprivate var contentRuleList: WKContentRuleList?
    @Published var isDestroyed: Bool = false
    @Published var lastKnownTime: Double = 0
    @Published var duration: Double = 0
    // -1: uninitialized, 0: ended, 1: playing, 2: paused, others per YT API
    @Published var playerState: Int = -1
    // Dynamic frame color sampling (used for ambient blur in normal video view)
    @Published var sampledColor: NSColor? = nil
    fileprivate var colorTimer: Timer?
    fileprivate var colorSamplingActive = false
    func startColorSampling(interval: TimeInterval = 0.7) {
        // Avoid duplicate timers
        stopColorSampling()
        colorSamplingActive = true
        colorTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            // Timer closure actor-izole değil; ana aktöre hop et.
            guard let self else { return }
            Task { @MainActor in self.sampleColorOnce() }
        }
    }
    func stopColorSampling() {
        colorSamplingActive = false
        colorTimer?.invalidate()
        colorTimer = nil
    }
    private func sampleColorOnce() {
        guard colorSamplingActive, let wv = webView else { return }
        let config = WKSnapshotConfiguration()
        // Downscale to improve performance; we just need an average color
        config.snapshotWidth = 160
        wv.takeSnapshot(with: config) { [weak self] image, _ in
            guard let self = self, let img = image else { return }
            if let avg = Self.averageColor(from: img) {
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        self.sampledColor = avg
                    }
                }
            }
        }
    }
    private static func averageColor(from image: NSImage) -> NSColor? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let width = 1
        let height = 1
        let bitsPerComponent = 8
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &pixelData,
                                  width: width,
                                  height: height,
                                  bitsPerComponent: bitsPerComponent,
                                  bytesPerRow: bytesPerRow,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .low
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        let r = CGFloat(pixelData[0]) / 255.0
        let g = CGFloat(pixelData[1]) / 255.0
        let b = CGFloat(pixelData[2]) / 255.0
        let a = CGFloat(pixelData[3]) / 255.0
        return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
    func play() {
        // Try primary player; if not available, attempt fallback iframe postMessage
        let js = "(function(){if(window.player&&player.playVideo){player.playVideo();return 'player';}var f=document.getElementById('fallback');if(f&&f.contentWindow){var msg={event:'command',func:'playVideo',args:[]};f.contentWindow.postMessage(JSON.stringify(msg),'*');return 'fallback';}return 'none';})();"
        webView?.evaluateJavaScript(js) { _, _ in }
    }
    func pause() {
        let js = "(function(){if(window.player&&player.pauseVideo){player.pauseVideo();return 'player';}var f=document.getElementById('fallback');if(f&&f.contentWindow){var msg={event:'command',func:'pauseVideo',args:[]};f.contentWindow.postMessage(JSON.stringify(msg),'*');return 'fallback';}return 'none';})();"
        webView?.evaluateJavaScript(js) { _, _ in }
    }
    func setVolume(percent: Int) {
        let p = max(0, min(percent, 100))
        let js = """
        (function(){
            try {
                // Persist desired volume for future loads
                window.__initialVolume = \(p);
                if (window.player && player.setVolume) {
                    try { if (\(p) === 0 && player.mute) { player.mute(); } else if (player.unMute) { player.unMute(); } } catch(_){}
                    player.setVolume(\(p));
                    return 'player';
                }
                var f = document.getElementById('fallback');
                if (f && f.contentWindow) {
                    try {
                        if (\(p) === 0) {
                            f.contentWindow.postMessage(JSON.stringify({event:'command',func:'mute',args:[]}), '*');
                        } else {
                            f.contentWindow.postMessage(JSON.stringify({event:'command',func:'unMute',args:[]}), '*');
                        }
                        f.contentWindow.postMessage(JSON.stringify({event:'command',func:'setVolume',args:[\(p)]}), '*');
                    } catch(_){}
                    return 'fallback';
                }
            } catch(e){}
            return 'none';
        })();
        """
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }
    func currentTime(completion: @escaping (Double)->Void) {
        webView?.evaluateJavaScript("player && player.getCurrentTime && player.getCurrentTime();") { result, _ in
            completion(result as? Double ?? 0)
        }
    }
    func fetchDuration(completion: @escaping (Double)->Void) {
        webView?.evaluateJavaScript("player && player.getDuration && player.getDuration();") { result, _ in
            let d = result as? Double ?? 0
            if d > 0 { DispatchQueue.main.async { self.duration = d } }
            completion(d)
        }
    }
    /// Load a new video id into the current player (without recreating WKWebView).
    /// Falls back to replacing the fallback iframe src if primary player is not available.
    func load(videoId: String, autoplay: Bool) {
        let auto = autoplay ? 1 : 0
        let js = """
        (function(){
            try {
                var auto = \(auto);
                // Remember autoplay wish and reset volumeApplied for fallback loop
                window.__wantsAutoplay = auto;
                try { window.volumeApplied = false; } catch(_) {}
                if (window.player && player.loadVideoById) {
                    player.loadVideoById({'videoId': '\(videoId)', 'startSeconds': 0});
                    var desired = (typeof window.__initialVolume === 'number' && window.__initialVolume >= 0) ? window.__initialVolume : -1;
                    if (desired >= 0) {
                        try {
                            if (desired === 0) { if (player.mute) player.mute(); }
                            else { if (player.unMute) player.unMute(); }
                            if (player.setVolume) player.setVolume(desired);
                        } catch(_){}
                    }
                    if (auto === 1 && player.playVideo) { player.playVideo(); }
                    return 'player';
                }
                var f = document.getElementById('fallback');
                if (f && f.contentWindow) {
                    var src = 'https://www.youtube-nocookie.com/embed/\(videoId)?autoplay=0&controls=1&rel=0&playsinline=1&start=0&modestbranding=1&fs=0&iv_load_policy=3&disablekb=1&enablejsapi=1';
                    f.src = src;
                    return 'fallback';
                }
                return 'none';
            } catch(e){ return 'error:' + (e && e.message); }
        })();
        """
        webView?.evaluateJavaScript(js, completionHandler: nil)
        DispatchQueue.main.async {
            self.lastKnownTime = 0
            self.duration = 0
        }
        // Ask for duration shortly after switching to populate progress bar quickly
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            self.fetchDuration { _ in }
        }
        // One-shot gentle retry: if duration is still 0 after 0.6s, poke play and re-fetch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            if self.duration <= 0 {
                // Send an extra play command in case the player ignored autoplay
                self.play()
                self.fetchDuration { _ in }
            }
        }
    }
    // Yeni: Belirli bir zamana atlamak için (yorum veya açıklamadaki timestamp tıklanınca)
    func seek(to seconds: Double) {
        let js = """
        (function(){
            try {
                if (window.player && player.seekTo) {
                    player.seekTo(\(seconds), true);
                    if (player.playVideo) { player.playVideo(); }
                    return 'player';
                }
                var f = document.getElementById('fallback');
                if (f && f.contentWindow) {
                    var msgSeek = {event:'command',func:'seekTo',args:[\(seconds), true]};
                    var msgPlay = {event:'command',func:'playVideo',args:[]};
                    f.contentWindow.postMessage(JSON.stringify(msgSeek), '*');
                    f.contentWindow.postMessage(JSON.stringify(msgPlay), '*');
                    return 'fallback';
                }
                return 'none';
            } catch(e){ return 'error:' + (e && e.message); }
        })();
        """
        webView?.evaluateJavaScript(js) { result, error in
            #if DEBUG
            if let error = error { print("[Seek] JS error: \(error)") }
            else if let r = result { print("[Seek] mode=\(r)") }
            #endif
        }
    }
    func destroy() {
        guard let wv = webView else { return }
        wv.stopLoading()
        wv.navigationDelegate = nil
        wv.uiDelegate = nil
        wv.configuration.userContentController.removeAllUserScripts()
        if let crl = contentRuleList { wv.configuration.userContentController.remove(crl) }
        wv.loadHTMLString("<html></html>", baseURL: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak wv] in
            wv?.removeFromSuperview()
        }
    stopColorSampling()
    isDestroyed = true
    webView = nil
    }

    // Relative seek (e.g., arrow keys) for both player and fallback via JS helper
    func seekRelative(by delta: Double) {
        webView?.evaluateJavaScript("window.__seekRelative && window.__seekRelative(\(delta));", completionHandler: nil)
    }
}

// EN: NSViewRepresentable wrapper that builds the WKWebView and injects the player HTML. TR: WKWebView oluşturan ve oynatıcı HTML’ini enjekte eden NSViewRepresentable sarmalayıcısı.
struct LightYouTubeEmbed: NSViewRepresentable {
    let videoId: String
    let startSeconds: Double
    let autoplay: Bool
    // Shorts gibi tamamen temiz arayüz istenen durumlar için dışarıdan parametre.
    let forceHideAll: Bool
    // Sadece ilerleme çubuğu görünür olsun (oynat/durdur vb. butonlar gizli) istenirse.
    let showOnlyProgressBar: Bool
    // Ayarlardaki görünüm değişikliklerini uygula (Shorts'ta kapalı tutacağız)
    let applyAppearanceSettings: Bool
    // Only normal video view enables this; Shorts keeps it off
    var enableColorSampling: Bool = false
    // Yeni: İlk yüklemede uygulanacak ses yüzdesi (0-100). Nil ise dokunma.
    var initialVolumePercent: Int? = nil
    @ObservedObject var controller: LightYouTubeController
    var onReady: () -> Void = {}
    // If true, disable native right-click context menu for this embed only
    var disableContextMenu: Bool = false
    // Snapshot of appearance settings (read once – restart app after changing settings).
    private let appearance = PlayerAppearanceSettings()

    // Static content blocker manager (single compile, reused for all players in process)
    private static let ruleListIdentifier = "ytHideUI"
    private static var compiling = false
    private static var compiledRuleList: WKContentRuleList? = nil
    private static var lastSelectorsHash: Int? = nil
    private static func ensureRuleList(selectors: String, completion: @escaping (WKContentRuleList?)->Void) {
        let hash = selectors.hashValue
        if let rl = compiledRuleList, lastSelectorsHash == hash { completion(rl); return }
        if compiling {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { ensureRuleList(selectors: selectors, completion: completion) }
            return
        }
        compiling = true
                let json = """
                [
                    {"trigger":{"url-filter": ".*", "if-domain":["www.youtube.com","youtube.com","www.youtube-nocookie.com","youtube-nocookie.com"]},"action":{"type":"css-display-none","selector":"\(selectors)"}}
                ]
                """
        let identifier = ruleListIdentifier + "-" + String(hash)
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json) { list, error in
            if let error = error { print("Content rule list compile error: \(error)") }
            compiledRuleList = list
            lastSelectorsHash = hash
            compiling = false
            completion(list)
        }
    }

    init(videoId: String, startSeconds: Double, autoplay: Bool, forceHideAll: Bool = false, showOnlyProgressBar: Bool = false, applyAppearanceSettings: Bool = true, enableColorSampling: Bool = false, initialVolumePercent: Int? = nil, controller: LightYouTubeController, onReady: @escaping () -> Void = {}, disableContextMenu: Bool = false) {
        self.videoId = videoId
        self.startSeconds = startSeconds
        self.autoplay = autoplay
        self.forceHideAll = forceHideAll
        self.showOnlyProgressBar = showOnlyProgressBar
        self.applyAppearanceSettings = applyAppearanceSettings
        self.enableColorSampling = enableColorSampling
        self.initialVolumePercent = initialVolumePercent
        self.controller = controller
        self.onReady = onReady
        self.disableContextMenu = disableContextMenu
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Use default data store so YouTube can persist visitor cookies reliably.
        // Ephemeral store may cause intermittent "Video unavailable" on first load.
        config.websiteDataStore = .default()
        if #available(macOS 14.0, *) {
            config.mediaTypesRequiringUserActionForPlayback = []
        }
        // Fullscreen istenmiyor: içerikten fullscreen taleplerini devre dışı bırak
        // Public API varsa onu, yoksa KVC anahtarlarını kullan.
        let prefs = config.preferences
        if prefs.responds(to: Selector(("setElementFullscreenEnabled:"))) {
            prefs.setValue(false, forKey: "elementFullscreenEnabled")
        }
        // Legacy key on macOS
        prefs.setValue(false, forKey: "fullScreenEnabled")
    let wv = PassthroughWKWebView(frame: .zero, configuration: config)
        wv.disableContextMenu = disableContextMenu
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator
    controller.webView = wv
    // isDestroyed başlangıçta zaten false; burada tekrar publish etmeyerek
    // "Publishing changes from within view updates" uyarısını önlüyoruz.
    // Initial load with appearance settings (snapshot at creation; no live updates)
    load(videoId: videoId, start: startSeconds, autoplay: autoplay, into: wv, coordinator: context.coordinator)
        return wv
    }

    func updateNSView(_ wv: WKWebView, context: Context) {
        // Intentionally no-op on videoId changes: HiddenAudioPlayerView uses controller.load(videoId:)
        // to switch in-place without rebuilding the entire HTML, which is more stable for telemetry.
    }

    private func load(videoId: String, start: Double, autoplay: Bool, into webView: WKWebView, coordinator: Coordinator) {
    let auto = autoplay ? 1 : 0
    // If no initial volume is provided (normal videos), keep as -1 so JS won’t mute/unmute implicitly.
    let initVol: Int = {
        if let p = initialVolumePercent { return max(0, min(p, 100)) }
        return -1
    }()
        coordinator.readyFired = false
    // Remove previous rule list if any (only on explicit reload, not dynamic updates)
    if let crl = controller.contentRuleList { webView.configuration.userContentController.remove(crl); controller.contentRuleList = nil }
        // Build combined selector string from toggles (join with commas). If nothing selected -> empty string (no rule list).
    var selectorList: [String] = {
            // Her durumda gizli kalacak öğeler (ayar bağımsız): Fullscreen ve PiP
            var s: [String] = [
        // Fullscreen ve PiP butonlarını gizle
        "button.ytp-fullscreen-button, .ytp-fullscreen-button, button.ytp-picture-in-picture-button, .ytp-pip-button"
            ]
            // Çıkışta görünen büyük play overlay ve pause overlay'i her zaman gizle
            s.append(".ytp-large-play-button")
            s.append(".ytp-pause-overlay")
            // Settings toggles only if enabled for this embed (normal videolar)
            guard applyAppearanceSettings else { return s }
            if appearance.hideChannelAvatar { s.append(".ytp-title-channel-logo") }
            if appearance.hideChannelName { s.append(".ytp-title-channel, .ytp-title-channel-logo + .ytp-title-text .ytp-title-channel") }
            if appearance.hideVideoTitle { s.append(".ytp-title-text, .ytp-title, .ytp-title-link") }
            if appearance.hideMoreVideosOverlay { s.append(".ytp-endscreen-content, .ytp-endscreen-layout, .ytp-ce-element, .ytp-pause-overlay, .ytp-show-cards-title") }
            if appearance.hideContextMenu { s.append(".ytp-contextmenu, .ytp-popup.ytp-contextmenu") }
            if appearance.hideWatchLater { s.append("button.ytp-watch-later-button") }
            if appearance.hideShare { s.append("button.ytp-share-button") }
            if appearance.hideSubtitlesButton { s.append("button.ytp-subtitles-button") }
            if appearance.hideQualityButton { s.append("button.ytp-settings-button") }
            if appearance.hideYouTubeLogo { s.append("a.ytp-youtube-button, .ytp-youtube-button, .ytp-watermark, .branding-img") }
            if appearance.hideAirPlayButton { s.append("button.ytp-airplay-button") }
            if appearance.hideChapterTitle { s.append(".ytp-chapter-container, .ytp-chapter-title") }
            if appearance.hideScrubPreview { s.append(".ytp-tooltip.ytp-preview, .ytp-tooltip.ytp-bottom, .ytp-scrubber-pull-indicator, .ytp-tooltip-text-wrapper, .ytp-tooltip-image, .ytp-tooltip-image .ytp-fast-thumbnail") }
            return s
        }()

    if forceHideAll {
            // Shorts için tüm overlay / buton / başlık / gradient katmanlarını kaldır.
            let extra: [String] = [
                ".ytp-chrome-top",
                ".ytp-chrome-bottom",
                ".ytp-gradient-top",
                ".ytp-gradient-bottom",
                ".ytp-title",
                ".ytp-title-text",
                ".ytp-title-channel",
                ".ytp-title-channel-logo",
                ".ytp-watermark",
                ".branding-img",
                ".ytp-button",
                ".ytp-right-controls",
                ".ytp-left-controls",
                ".ytp-spinner",
                ".ytp-pause-overlay",
                ".ytp-endscreen-content",
                ".ytp-endscreen-layout",
                ".ytp-ce-element",
                ".ytp-show-cards-title",
                ".ytp-cards-button-icon",
                ".ytp-panel",
                ".ytp-tooltip",
                ".ytp-contextmenu"
            ]
            selectorList.append(contentsOf: extra)
        } else if showOnlyProgressBar {
            // Progress bar + play ve ses (volume) butonları kalsın.
            // Not hiding .ytp-left-controls (play, volume, time). Time göstergesi istenmiyorsa ayrıca gizlenir.
            let extra: [String] = [
                ".ytp-chrome-top",
                ".ytp-gradient-top",
                ".ytp-gradient-bottom",
                ".ytp-title",
                ".ytp-title-text",
                ".ytp-title-channel",
                ".ytp-title-channel-logo",
                ".ytp-watermark",
                ".branding-img",
                // Sağ kontrol grubunu tamamen gizlemek yerine sadece istemediğimiz butonları gizle:
                // (fullscreen, theater/size, mini-player, remote cast vs). Quality (settings) ve subtitles görünür kalsın.
                ".ytp-right-controls .ytp-fullscreen-button",
                ".ytp-right-controls .ytp-size-button",
                ".ytp-right-controls .ytp-miniplayer-button",
                ".ytp-right-controls .ytp-remote-button",
                // PIP butonu (ayrıca appearance ile de gizlenebilir)
                ".ytp-right-controls .ytp-pip-button",
                // Hide overlays & tooltips & context
                ".ytp-spinner",
                ".ytp-pause-overlay",
                ".ytp-endscreen-content",
                ".ytp-endscreen-layout",
                ".ytp-ce-element",
                ".ytp-show-cards-title",
                ".ytp-cards-button-icon",
                ".ytp-tooltip",
                ".ytp-contextmenu",
                // Opsiyonel: süre metni gizle (sadece çubuk + ikonlar)
                ".ytp-time-display"
            ]
            selectorList.append(contentsOf: extra)
        }

        let combinedSelectors = selectorList.joined(separator: ",")

        func proceed() {
            // Construct HTML after (so rule list active when iframe created)
            // İstek üzerine tüm modlarda controls=1 kullan
            let controlsValue: Int = 1
            let html = """
            <html><head><meta name=viewport content='initial-scale=1.0'>
            <style>html,body,#player,#fallback{margin:0;padding:0;background:#000;height:100%;width:100%;overflow:hidden;}html,body{position:relative}::-webkit-media-controls{display:none !important;}</style>
            <script>
            window.__ytDebug=function(m){try{window.webkit.messageHandlers.ytEvent.postMessage(m);}catch(e){}}
            // Track last known time for both player and fallback paths
            window.__lastTime = 0;
            // İlk yüklemede uygulanacak ses yüzdesi (<0 ise yok say). 0, mute kabul edilir.
            window.__initialVolume = \(initVol);
            // Otomatik oynatma isteği (oynatmayı, sesi uyguladıktan sonra tetikleyeceğiz)
            window.__wantsAutoplay = \(auto);
            // Fallback iframe mesajlarını dinle (currentTime bilgisi dahil)
            window.addEventListener('message', function(event){
                try{
                    var data = event && event.data;
                    if (typeof data === 'string') { try{ data = JSON.parse(data);}catch(_){}}
                    if (data && data.info && typeof data.info.currentTime === 'number') {
                        window.__lastTime = +data.info.currentTime || 0;
                        try{ window.webkit.messageHandlers.ytEvent.postMessage('time:'+data.info.currentTime); }catch(e){}
                    }
                    if (data && data.info && typeof data.info.duration === 'number') {
                        try{ window.webkit.messageHandlers.ytEvent.postMessage('duration:'+data.info.duration); }catch(e){}
                    }
                }catch(e){}
            });
            // Helper to seek relatively by delta seconds for both modes
            window.__seekRelative = function(delta){
                try{
                    if (window.player && player.getCurrentTime && player.seekTo) {
                        var t = +player.getCurrentTime();
                        var nt = Math.max(0, (isFinite(t)?t:0) + delta);
                        player.seekTo(nt, true);
                        return 'player';
                    }
                    var f = document.getElementById('fallback');
                    if (f && f.contentWindow) {
                        var nt = Math.max(0, (isFinite(window.__lastTime)?window.__lastTime:0) + delta);
                        var msgSeek = {event:'command',func:'seekTo',args:[nt, true]};
                        f.contentWindow.postMessage(JSON.stringify(msgSeek), '*');
                        return 'fallback';
                    }
                }catch(e){}
                return 'none';
            }
            </script>
            <script src='https://www.youtube.com/iframe_api'></script>
            <script>
            var player;var ready=false;var fallbackStarted=false;var timePoller=null;var volumeApplied=false;var autoplayNudged=false;function onYouTubeIframeAPIReady(){try{player=new YT.Player('player',{host:'https://www.youtube-nocookie.com',videoId:'\(videoId)', playerVars:{autoplay:0,controls:controlsValue,rel:0,playsinline:1,start:\(Int(start)),origin:'https://www.youtube-nocookie.com',modestbranding:1,fs:0,iv_load_policy:3,disablekb:1}, events:{onReady:function(){ready=true;window.__ytDebug('ready');try{window.webkit.messageHandlers.ytReady.postMessage('r');}catch(e){};try{if(typeof window.__initialVolume==='number'&&window.__initialVolume>=0){try{if(window.__initialVolume===0){if(player.mute)player.mute();}else{if(player.unMute)player.unMute();} if(player.setVolume)player.setVolume(window.__initialVolume);volumeApplied=true;}catch(_){} } if(window.__wantsAutoplay===1 && player.playVideo){player.playVideo(); setTimeout(function(){try{var st=player.getPlayerState?player.getPlayerState():-1;if(st!==1&&player.playVideo){player.playVideo();}}catch(_){}} ,350); setTimeout(function(){try{var st=player.getPlayerState?player.getPlayerState():-1;if(st!==1&&player.playVideo){player.playVideo();}}catch(_){}} ,900);} if(timePoller)clearInterval(timePoller);timePoller=setInterval(function(){try{if(player){if(player.getCurrentTime){var t=player.getCurrentTime(); if(t>0){window.__lastTime = +t || 0; window.webkit.messageHandlers.ytEvent.postMessage('time:'+t);}} if(player.getDuration){var d=player.getDuration(); if(d>0){window.webkit.messageHandlers.ytEvent.postMessage('duration:'+d);}}}}catch(_){}} ,500);}catch(_){}} ,onError:function(e){window.__ytDebug('error:'+(e&&e.data));try{startFallback();}catch(_){}} ,onStateChange:function(s){window.__ytDebug('state:'+(s&&s.data));}}});}catch(err){window.__ytDebug('constructErr');startFallback();}}
            function startFallback(){if(fallbackStarted||ready)return;fallbackStarted=true;document.getElementById('player').outerHTML="<iframe id='fallback' src='https://www.youtube-nocookie.com/embed/\(videoId)?autoplay=0&controls=\(controlsValue)&rel=0&playsinline=1&start=\(Int(start))&modestbranding=1&fs=0&iv_load_policy=3&disablekb=1&enablejsapi=1' frameborder='0' allow='autoplay; picture-in-picture; encrypted-media' style='width:100%;height:100%;'></iframe>";try{window.webkit.messageHandlers.ytReady.postMessage('fallback');}catch(e){};try{if(timePoller)clearInterval(timePoller);timePoller=setInterval(function(){var f=document.getElementById('fallback');if(!f||!f.contentWindow)return;try{f.contentWindow.postMessage(JSON.stringify({event:'listening',id:'light-yt'}),'*');if(typeof window.__initialVolume==='number'&&window.__initialVolume>=0&&!volumeApplied){ if(window.__initialVolume===0){f.contentWindow.postMessage(JSON.stringify({event:'command',func:'mute',args:[]}),'*');} else {f.contentWindow.postMessage(JSON.stringify({event:'command',func:'unMute',args:[]}),'*');} f.contentWindow.postMessage(JSON.stringify({event:'command',func:'setVolume',args:[window.__initialVolume]}),'*'); volumeApplied=true; } if(window.__wantsAutoplay===1 && !autoplayNudged){ f.contentWindow.postMessage(JSON.stringify({event:'command',func:'playVideo',args:[]}),'*'); autoplayNudged=true; } f.contentWindow.postMessage(JSON.stringify({event:'command',func:'getCurrentTime',args:[]}),'*');f.contentWindow.postMessage(JSON.stringify({event:'command',func:'getDuration',args:[]}),'*');}catch(_){}} ,500);}catch(_){}}
            setTimeout(function(){if(!ready)startFallback();},3500);
            </script></head><body><div id='player'></div></body></html>
            """
            // Register handlers (re-add each load)
            webView.configuration.userContentController.removeAllUserScripts() // keep rule lists
            if disableContextMenu {
                let js = "document.addEventListener('contextmenu', function(e){ try{ e.preventDefault(); e.stopPropagation(); }catch(_){} return false; }, {capture:true});"
                let script = WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: false)
                webView.configuration.userContentController.addUserScript(script)
            }
            let handler = coordinator.readyHandler
            webView.configuration.userContentController.add(handler, name: "ytReady")
            webView.configuration.userContentController.add(handler, name: "ytEvent")
            webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube-nocookie.com"))
        }

        if combinedSelectors.isEmpty {
            proceed() // nothing to hide
        } else {
            Self.ensureRuleList(selectors: combinedSelectors) { [weak controller, weak webView] list in
                // WKWebView yaşam döngüsü veya controller yoksa erken çık
                guard let webView, let controller else { return }
                if let list = list {
                    // UI / model güncellemeleri ana aktörde
                    Task { @MainActor in
                        webView.configuration.userContentController.add(list)
                        controller.contentRuleList = list
                        proceed()
                    }
                } else {
                    Task { @MainActor in proceed() }
                }
            }
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate {
        var parent: LightYouTubeEmbed
        var lastVideoId: String
        var readyFired = false
        lazy var readyHandler: WKScriptMessageHandler = self
        init(_ parent: LightYouTubeEmbed) { self.parent = parent; self.lastVideoId = parent.videoId }
        // Allow window.open-style fullscreen popups (some flows may attempt it)
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            return nil // Use same webView, no external windows
        }
        func webViewDidClose(_ webView: WKWebView) {}
        // Note: macOS WebKit lacks public context menu filtering APIs used on iOS.
        // We suppress via PassthroughWKWebView.menu(for:) plus a top overlay that captures right-clicks.
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "ytReady" {
                guard !readyFired else { return }
                readyFired = true
                parent.onReady()
                // ready – nothing else needed; content rule list already applied
            } else if message.name == "ytEvent" {
                #if DEBUG
                // Debug: observe incoming events to diagnose progress updates
                // print("[LightYT] event: \(message.body)")
                #endif
                if let body = message.body as? String, body.hasPrefix("time:") {
                    let str = String(body.dropFirst(5))
                    if let t = Double(str) { parent.controller.lastKnownTime = t }
                }
                if let body = message.body as? String, body.hasPrefix("duration:") {
                    let str = String(body.dropFirst(9))
                    if let d = Double(str) { parent.controller.duration = d }
                }
                if let body = message.body as? String, body.contains("state:") {
                    // Parse numeric state after 'state:' safely
                    if let range = body.range(of: "state:") {
                        let suffix = String(body[range.upperBound...])
                        let trimmed = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let val = Int(trimmed) {
                            parent.controller.playerState = val
                        }
                    }
                }
                if !readyFired, let body = message.body as? String, body.contains("state:1") { // playing
                    readyFired = true
                    parent.onReady()
                }
                // Start/stop color sampling based on player state when enabled
                if parent.enableColorSampling, let body = message.body as? String, body.contains("state:") {
                    if body.contains("state:1") { // playing
                        Task { @MainActor in parent.controller.startColorSampling() }
                    } else if body.contains("state:0") || body.contains("state:2") { // ended or paused
                        Task { @MainActor in parent.controller.stopColorSampling() }
                    }
                }
            }
        }
    }
}
// Removed old multi-rule builder & JSON escape helper (replaced by combined selector rule above).
