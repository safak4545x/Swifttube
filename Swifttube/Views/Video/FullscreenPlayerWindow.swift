/*
 Overview / Genel Bakış
 EN: Borderless fullscreen player window that transfers time and coordinates exit/restore with the main UI.
 TR: Zaman aktaran ve ana UI ile çıkış/geri yüklemeyi koordine eden kenarlıksız tam ekran oynatıcı penceresi.
*/

// EN: SwiftUI/AppKit interop for a custom fullscreen NSWindow host. TR: Özel tam ekran NSWindow barındırmak için SwiftUI/AppKit birlikte çalışması.
import SwiftUI
import AppKit

// EN: Dedicated fullscreen overlay window for video only. TR: Sadece video için ayrılmış tam ekran üst pencere.
@MainActor
final class FullscreenPlayerWindow: NSObject, NSWindowDelegate {
    static let shared = FullscreenPlayerWindow()

    private var window: NSWindow?
    private var onClose: ((Double?) -> Void)?
    private var pendingReturnTime: Double?
    private var isInFullScreen = false
    private var shouldCloseAfterExitingFullScreen = false
    private var controller: LightYouTubeController?
    private var currentVideoId: String?

    // Global state helpers like MiniPlayerWindow
    var isPresented: Bool { window != nil }
    var activeVideoId: String? { currentVideoId }

    // EN: Create and present the fullscreen window; capture onClose for time handoff. TR: Tam ekran pencereyi oluşturup göster; kapanışta zaman devri için onClose yakalanır.
    func present(videoId: String, startAt: Double, onClose: @escaping (Double?) -> Void) {
        // TR: Zaten bir pencere varsa önce düzgün kapat. EN: Close existing window first if any.
        if window != nil { requestClose(with: nil) }
        self.onClose = onClose

    // EN: Shared controller owned by the window to query time on close. TR: Kapanışta süre okumak için pencerenin sahip olduğu paylaşılan denetleyici.
    let controller = LightYouTubeController()
    self.controller = controller
    self.currentVideoId = videoId
    let content = FullscreenPlayerContent(videoId: videoId, startSeconds: startAt, controller: controller) { [weak self] seconds in
            // EN: Close request with returned time. TR: Zaman iadesiyle kapanış isteği.
            self?.requestClose(with: seconds)
        }
        let hosting = NSHostingView(rootView: content)

        // EN: Configure borderless-like window suitable for native fullscreen Space. TR: Yerel tam ekran Space için uygun pencere yapılandırması.
        let w = NSWindow(contentRect: NSScreen.main?.frame ?? .zero,
                         styleMask: [.titled, .resizable, .fullSizeContentView, .closable, .miniaturizable],
                         backing: .buffered,
                         defer: false)
        w.isReleasedWhenClosed = false
        w.backgroundColor = .black
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.collectionBehavior = [.fullScreenPrimary, .fullScreenAllowsTiling]
        w.hasShadow = false
        w.ignoresMouseEvents = false
        w.isOpaque = true
        w.delegate = self
        w.contentView = hosting

        // EN: Cover entire screen (main display). TR: Tüm ekranı kapla (ana ekran).
        if let screen = NSScreen.main {
            w.setFrame(screen.frame, display: true)
        }

        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // EN: Enter native fullscreen Space shortly after creation. TR: Oluşturduktan kısa süre sonra yerel tam ekran Space’e geç.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            w.toggleFullScreen(nil)
        }

        self.window = w
    }

    // EN: External close request (ESC/X or programmatic). TR: Dışarıdan kapatma isteği (ESC/X veya programatik).
    func requestClose(with time: Double?) {
        pendingReturnTime = time
        guard let w = window else {
            // EN: No window: just forward callback with last time. TR: Pencere yoksa sadece geri çağrıyı ilet.
            onClose?(pendingReturnTime)
            onClose = nil
            pendingReturnTime = nil
            return
        }
        // EN: If in fullscreen, exit first; then close. TR: Fullscreen ise önce çık; sonra kapat.
        if isInFullScreen {
            shouldCloseAfterExitingFullScreen = true
            w.toggleFullScreen(nil)
        } else {
            actuallyClose()
        }
    }

    private func actuallyClose() {
        guard let w = window else { return }
        // EN: Standard close; OS handles animation and Space return. TR: Standart kapatma; animasyon ve Space dönüşünü OS yönetir.
        w.close()
    }

    // MARK: - NSWindowDelegate
    func windowDidEnterFullScreen(_ notification: Notification) { isInFullScreen = true }
    func windowDidExitFullScreen(_ notification: Notification) {
        isInFullScreen = false
        // EN: ESC may be handled by system; try to read current time before closing to avoid resetting to 0. TR: ESC bazen sistemce işlenir; kapanmadan önce süreyi okumayı dene ki 0’a dönmeyelim.
        let finalizeClose: () -> Void = { [weak self] in
            guard let self else { return }
            self.shouldCloseAfterExitingFullScreen = false
            DispatchQueue.main.async { [weak self] in
                if self?.window != nil { self?.actuallyClose() }
            }
        }

        if pendingReturnTime == nil, let c = controller {
            c.currentTime { [weak self] t in
                guard let self else { return }
                let direct = (t > 0 ? t : nil)
                let fromEvents = (c.lastKnownTime > 0 ? c.lastKnownTime : nil)
                self.pendingReturnTime = direct ?? fromEvents ?? self.pendingReturnTime
                finalizeClose()
            }
        } else {
            finalizeClose()
        }
    }
    func windowWillClose(_ notification: Notification) {
        // EN: Single exit point for cleanup and callback. TR: Temizlik ve geri bildirim için tek çıkış noktası.
        let cb = onClose
        let returned = pendingReturnTime
        let vId = currentVideoId
        // Temizle
        window?.delegate = nil
        window?.contentView = nil
        window = nil
        onClose = nil
        pendingReturnTime = nil
        isInFullScreen = false
        shouldCloseAfterExitingFullScreen = false
        controller = nil
        currentVideoId = nil
        // EN: Broadcast a global stop to prevent background playback. TR: Arka plan oynatımını engellemek için global stop yayınla.
    NotificationCenter.default.post(name: .stopAllVideos, object: nil)
        // Zaman bilgisini ilet
        cb?(returned)
        // EN: Persist final time for later resume. TR: Daha sonra devam edebilmek için süreyi kalıcı kaydet.
        if let vId, let t = returned {
            Task { await PlaybackProgressStore.shared.save(videoId: vId, seconds: t) }
        }
    }
}

// EN: SwiftUI content embedded in the fullscreen window. TR: Tam ekran pencerede gömülü SwiftUI içerik.
private struct FullscreenPlayerContent: View {
    let videoId: String
    let startSeconds: Double
    let controller: LightYouTubeController
    var onCloseWithTime: (Double?) -> Void
    @State private var ready = false
    @State private var lastObservedTime: Double = 0
    @State private var timeSampler: Timer?
    // EN: Auto-hide logic for the close button. TR: Kapat düğmesi için otomatik gizleme mantığı.
    @State private var showClose = true
    @State private var lastMouseActivityAt = Date()
    @State private var hideWorkItem: DispatchWorkItem? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            // EN: Inline YouTube player with controller bridge and appearance settings. TR: Denetleyici köprüsü ve görünüm ayarlarıyla gömülü YouTube oynatıcı.
            LightYouTubeEmbed(
                videoId: videoId,
                startSeconds: startSeconds,
                autoplay: true,
                forceHideAll: false,
                showOnlyProgressBar: false,
                applyAppearanceSettings: true,
                controller: controller,
                onReady: {
                    withAnimation(.easeOut(duration: 0.18)) { ready = true }
                    // Süre örnekleyici: olası fallback durumunda bile zaman kaydetmeyi dene
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
            .ignoresSafeArea()

            // EN: Close control (blurred bg + auto-hide). TR: Kapat kontrolü (blur arka plan + otomatik gizleme).
            VStack { Spacer(minLength: 0) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topTrailing) {
                    Button(action: requestClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 10)
                    .padding(.trailing, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.22), value: showClose)
                    .opacity(showClose ? 1 : 0)
                    .offset(y: showClose ? 0 : -24)
                }
        }
        // EN: Mouse move/exit: manage auto-hide visibility. TR: Fare hareket/çıkış: otomatik gizlemeyi yönet.
        .overlay {
            MouseActivityView { event in
                switch event {
                case .entered, .moved:
                    lastMouseActivityAt = Date()
                    if !showClose { withAnimation { showClose = true } }
                    scheduleAutoHide()
                case .exited:
                    hideImmediately()
                }
            }
            .allowsHitTesting(false)
        }
        .onAppear {
            if startSeconds > 0 {
                // Başta 0'a reseti engellemek için explicit pause->seek->play uygula
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    controller.pause()
                    controller.seek(to: startSeconds)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        controller.play()
                    }
                }
            } else {
                controller.play()
            }
            // İlk anda da zamanı okumayı dene
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                Task { @MainActor in
                    controller.currentTime { t in if t > 0 { lastObservedTime = t } }
                }
            }
        }
        .onDisappear {
            timeSampler?.invalidate(); timeSampler = nil
            controller.pause(); controller.destroy()
            hideWorkItem?.cancel()
        }
        // Fullscreen açıkken gelen timestamp (seekToSeconds) isteklerini sadece bu videoyla eşleşiyorsa uygula
        .onReceive(NotificationCenter.default.publisher(for: .seekToSeconds)) { note in
            guard let secs = note.userInfo?["seconds"] as? Int else { return }
            guard let requestedId = note.userInfo?["videoId"] as? String, requestedId == videoId else { return }
            Task { @MainActor in
                controller.seek(to: Double(secs))
                controller.play()
            }
        }
        .background(KeyHandler(onEscape: requestClose, onArrow: { dir in
            let step = 5.0 * Double(dir)
            controller.seekRelative(by: step)
        }))
    }

    @MainActor private func requestClose() {
        controller.currentTime { secs in
            // Öncelik: anlık okunan süre > son örneklenen > JS event'lerinden lastKnownTime
            let fromDirect = secs > 0 ? secs : nil
            let fromSample = lastObservedTime > 0 ? lastObservedTime : nil
            let fromEvents = controller.lastKnownTime > 0 ? controller.lastKnownTime : nil
            let t = fromDirect ?? fromSample ?? fromEvents
            onCloseWithTime(t)
        }
    }
}

// EN: Helpers to schedule/hide the close control. TR: Kapat kontrolünü zamanlamak/gizlemek için yardımcılar.
private extension FullscreenPlayerContent {
    func scheduleAutoHide() {
        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [lastMouseActivityAt] in
            let elapsed = Date().timeIntervalSince(lastMouseActivityAt)
            if elapsed >= 3.0 {
                withAnimation { showClose = false }
            } else {
                scheduleAutoHide()
            }
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
    }

    func hideImmediately() { withAnimation { showClose = false } }
}

// EN: ESC/arrow key listener bridge (NSViewRepresentable). TR: ESC/ok tuşu dinleyici köprüsü (NSViewRepresentable).
private struct KeyHandler: NSViewRepresentable {
    var onEscape: () -> Void
    var onArrow: (Int) -> Void = { _ in } // -1 left, +1 right
    func makeNSView(context: Context) -> KeyView {
        let v = KeyView()
        v.onEscape = onEscape
        v.onArrow = onArrow
        return v
    }
    func updateNSView(_ nsView: KeyView, context: Context) {
        nsView.onEscape = onEscape
        nsView.onArrow = onArrow
    }
    final class KeyView: NSView {
        var onEscape: (() -> Void)?
        var onArrow: ((Int) -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func viewDidMoveToWindow() { window?.makeFirstResponder(self) }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { onEscape?(); return } // ESC
            // Left/Right arrows
            if let chars = event.charactersIgnoringModifiers, let uni = chars.unicodeScalars.first {
                if uni.value == 0xF702 { onArrow?(-1); return }
                if uni.value == 0xF703 { onArrow?(+1); return }
            }
            super.keyDown(with: event)
        }
    }
}
