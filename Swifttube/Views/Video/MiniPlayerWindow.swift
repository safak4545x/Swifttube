/*
 Overview / Genel Bakış
 EN: Always-on-top floating mini player (PiP-like) with simple controls and time handoff.
 TR: Basit kontroller ve zaman devri olan, her zaman üstte kayan mini oynatıcı (PiP benzeri).
*/

// EN: SwiftUI/AppKit bridge for a custom borderless floating window. TR: Özel kenarlıksız kayan pencere için SwiftUI/AppKit köprüsü.
import SwiftUI
import AppKit

// Küçük, her zaman üstte kalan mini oynatıcı penceresi (PiP benzeri)
// EN: Singleton manager for the mini player window lifecycle. TR: Mini oynatıcı pencere yaşam döngüsü için tekil yönetici.
final class MiniPlayerWindow: NSObject, NSWindowDelegate {
    static let shared = MiniPlayerWindow()

    private var window: NSWindow?
    private var onClose: ((Double?) -> Void)?
    private var pendingReturnTime: Double?
    private var currentVideoId: String?

    // Global state helpers
    var isPresented: Bool { window != nil }
    var activeVideoId: String? { currentVideoId }

    // EN: Create and show the mini window; onClose returns the last time when closed. TR: Mini pencereyi oluşturup göster; kapanışta son süreyi döndürür.
    func present(videoId: String, startAt: Double, onClose: @escaping (Double?) -> Void) {
        // TR: Zaten açık mini pencere varsa kapat. EN: Close existing mini window if present.
        if window != nil { requestClose(with: nil) }
        self.onClose = onClose
    self.currentVideoId = videoId
        
    let content = MiniPlayerContent(videoId: videoId, startSeconds: startAt) { [weak self] seconds in
            self?.requestClose(with: seconds)
        }
        // EN: Host SwiftUI content and allow hit-testing for controls. TR: SwiftUI içeriğini barındır ve kontroller için tıklamayı etkin tut.
    let hosting = NSHostingView(rootView: content)

        // 16:9 başlangıç boyutu
        let size = NSSize(width: 420, height: 236)
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        // Sağ-alt köşeye yerleştir
        let origin = NSPoint(x: screenFrame.maxX - size.width - 20, y: screenFrame.minY + 20)
        let frame = NSRect(origin: origin, size: size)

        // EN: Borderless, transparent background; rounded corners and shadow applied to content. TR: Kenarlıksız, şeffaf zemin; içerikte yuvarlatma ve gölge.
    let w = NSWindow(
            contentRect: frame,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
    w.isReleasedWhenClosed = false
    w.title = "Mini Player"
    w.backgroundColor = .clear
    w.isOpaque = false
        // EN: Apply corner radius via host view layer mask. TR: Köşe yuvarlama için host view katman maskesi uygula.
    hosting.wantsLayer = true
    hosting.layer?.cornerRadius = 12
    hosting.layer?.masksToBounds = true
    hosting.layer?.backgroundColor = NSColor.clear.cgColor

    w.level = .floating
    w.hasShadow = true
        w.delegate = self
        w.contentView = hosting
        // Minimum pencere boyutu (16:9 ~ 400x225)
        w.minSize = NSSize(width: 400, height: 225)
        // Yalnızca orantılı/çapraz boyutlandırma (16:9 kilidi)
        w.contentAspectRatio = NSSize(width: 16, height: 9)
        // Arka plan üzerinden pencereyi sürüklemeyi aç
        w.isMovableByWindowBackground = true
        // Başlık çubuğu dışında arka plan tıklamalarıyla da taşıyabilsin
        // 16:9'a yakın kalması için oransal olarak kısıtlamak zor; bırak esnek olsun.

        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: false)

    self.window = w
        // EN: Notify observers that mini player opened for this video. TR: Mini oynatıcı açıldı bilgisini yayınla.
    NotificationCenter.default.post(name: .miniPlayerOpened, object: nil, userInfo: ["videoId": videoId])
    }

    func requestClose(with time: Double?) {
        pendingReturnTime = time
        guard let w = window else {
            onClose?(pendingReturnTime)
            onClose = nil
            pendingReturnTime = nil
            return
        }
        w.close()
    }

    // MARK: - NSWindowDelegate
    func windowWillClose(_ notification: Notification) {
        let cb = onClose
        let returned = pendingReturnTime
        let vId = currentVideoId
        window?.delegate = nil
        window?.contentView = nil
        window = nil
        onClose = nil
        pendingReturnTime = nil
        currentVideoId = nil
    cb?(returned)
        // EN: Extra safety to stop any background playback. TR: Arka plan oynatımı durdurmak için ek güvenlik.
    NotificationCenter.default.post(name: .stopAllVideos, object: nil)
        if let vId {
            var info: [String: Any] = ["videoId": vId]
            if let returned { info["time"] = returned }
            NotificationCenter.default.post(name: .miniPlayerClosed, object: nil, userInfo: info)
        }
        // EN: Persist final time for future resume. TR: Daha sonra devam etmek için süreyi kaydet.
    if let vId, let t = returned { Task { await PlaybackProgressStore.shared.save(videoId: vId, seconds: t) } }
    }

    // En küçük boyutu daha sert biçimde uygula (drag ile aşılmasını önlemek için)
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let minW: CGFloat = 400
        let minH: CGFloat = 225
        let w = max(frameSize.width, minW)
        let h = max(frameSize.height, minH)
        return NSSize(width: w, height: h)
    }
}

// EN: SwiftUI content for the mini window with controls. TR: Kontrolleri olan mini pencere için SwiftUI içeriği.
private struct MiniPlayerContent: View {
    let videoId: String
    let startSeconds: Double
    var onCloseWithTime: (Double?) -> Void
    @EnvironmentObject var i18n: Localizer
    @StateObject private var controller = LightYouTubeController()
    @State private var lastObservedTime: Double = 0
    @State private var timeSampler: Timer?
    @State private var isPlaying: Bool = true

    var body: some View {
    ZStack {
            // EN: Video-only: all iframe UI hidden. TR: Yalnız video: iframe içindeki tüm UI gizli.
            LightYouTubeEmbed(
                videoId: videoId,
                startSeconds: startSeconds,
                autoplay: true,
                forceHideAll: true,
                showOnlyProgressBar: false,
                applyAppearanceSettings: false,
                controller: controller,
                onReady: {
                    timeSampler?.invalidate()
                    timeSampler = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                        Task { @MainActor in
                            controller.currentTime { t in
                                if t > 0 { lastObservedTime = t }
                            }
                        }
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            // EN: Full-surface dragging to move the window. TR: Pencereyi taşımak için tam yüzey sürükleme.
            DragToMoveWindowOverlay()
                .allowsHitTesting(true)
                .zIndex(0)

            // EN: Bottom bar controls: left Play/Pause, right PiP-exit (close). TR: Alt çubuk kontrolleri: solda Oynat/Duraklat, sağda PiP-çık (kapat).
            VStack {
                Spacer()
                HStack {
                    // Sol: Play/Pause
                    Button(action: togglePlay) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .zIndex(2)

                    Spacer()

                    // Sağ: PiP simgesi görünümüyle kapat
                    Button(action: requestClose) {
                        Image(systemName: "pip.exit")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .zIndex(2)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        // Tutarlı görünüm için hafif stroke ve gölge uygula
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 16, x: 0, y: 8)
        .ignoresSafeArea() // Borderless olduğu için safe area etkisi minimal; yine de full-bleed
        .onAppear {
            if startSeconds > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    controller.pause()
                    controller.seek(to: startSeconds)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { controller.play(); isPlaying = true }
                }
            } else {
                controller.play(); isPlaying = true
            }
            // İlk okumayı dene
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                Task { @MainActor in controller.currentTime { t in if t > 0 { lastObservedTime = t } } }
            }
        }
        // EN: Honor external seek requests only for the active videoId. TR: Dış arama isteklerini sadece aktif videoId için uygula.
        .onReceive(NotificationCenter.default.publisher(for: .seekToSeconds)) { note in
            guard let secs = note.userInfo?["seconds"] as? Int else { return }
            // Mini player yalnizca açık videonun ID'si ile eşleşen istekleri uygular
            guard let requestedId = note.userInfo?["videoId"] as? String, requestedId == videoId else { return }
            Task { @MainActor in
                controller.seek(to: Double(secs))
                controller.play(); isPlaying = true
            }
        }
        .onDisappear {
            timeSampler?.invalidate(); timeSampler = nil
            controller.pause(); controller.destroy()
        }
    }

    @MainActor private func requestClose() {
        controller.currentTime { secs in
            // Fallbacks: prefer direct time; else last sampled; else controller.lastKnownTime from JS events
            let fromDirect = secs > 0 ? secs : nil
            let fromSample = lastObservedTime > 0 ? lastObservedTime : nil
            let fromEvents = controller.lastKnownTime > 0 ? controller.lastKnownTime : nil
            let t = fromDirect ?? fromSample ?? fromEvents
            onCloseWithTime(t)
        }
    }

    @MainActor private func togglePlay() {
        if isPlaying {
            controller.pause(); isPlaying = false
        } else {
            controller.play(); isPlaying = true
        }
    }
}

// Not: Standart macOS penceresi kullanıldığı için özel sürükleme hosting'ine gerek yok.

// EN: Transparent AppKit layer to drag the NSWindow from the whole surface. TR: Tüm yüzeyden NSWindow'u sürüklemek için şeffaf AppKit katmanı.
private struct DragToMoveWindowOverlay: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView {
        let v = DragView(frame: .zero)
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.clear.cgColor
        return v
    }
    func updateNSView(_ nsView: DragView, context: Context) {}

    final class DragView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { self } // Tüm yüzeyi yakala; butonlar zIndex ile üstte
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
        override var isOpaque: Bool { false }
        override func draw(_ dirtyRect: NSRect) { /* clear */ }
    }
}
