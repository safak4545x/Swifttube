
/*
 File Overview (EN)
 Purpose: Container for Shorts list with per-item player instances, focus tracking, and context bar.
 Key Responsibilities:
 - Render vertically scrollable Shorts with per-item lifecycle
 - Track focus to start/stop playback and apply persistence
 - Offer quick actions: like, copy link, open channel, mute/repeat
 Used By: Shorts tab/page.

 Dosya Özeti (TR)
 Amacı: Öğeye özel oynatıcılar, odak takibi ve bağlam çubuğuyla Shorts liste konteyneri.
 Ana Sorumluluklar:
 - Dikey kaydırılabilir Shorts öğelerini, öğe başına yaşam döngüsüyle birlikte göstermek
 - Odağı takip ederek oynatmayı başlat/durdur ve kalıcılığı uygula
 - Hızlı eylemler: beğen, bağlantıyı kopyala, kanalı aç, sessize al/tekrar
 Nerede Kullanılır: Shorts sekmesi/sayfası.
*/

import SwiftUI
import AppKit

struct ShortsVideoView: View {
    @EnvironmentObject var i18n: Localizer
    let video: YouTubeVideo
    @ObservedObject var youtubeAPI: YouTubeAPIService
    @Binding var showComments: Bool
    @Binding var shouldPlay: Bool
    @State private var showShareMenu = false
    @State private var resolvedThumb: String = ""
    // Alt meta bloğunu biraz yukarı almak için ekstra bottom padding miktarı
    private let bottomMetaExtraLift: CGFloat = 40 // Hafifçe aşağı çekildi (ince ayar için değiştirilebilir)
    // Aksiyon butonları ayarları (kolay ince ayar için sabitler)
    private let actionIconSize: CGFloat = 22
    private let actionVerticalSpacing: CGFloat = 18
    private let actionRightPadding: CGFloat = 6
    private let actionBottomLift: CGFloat = 140 // 64 -> 80: Biraz daha yukarı taşındı (kullanıcı isteği)

    // Tek oyuncu: AVPlayer tabanlı embed
    @ViewBuilder
    private func playerEmbed() -> some View {
    // Tamamen temiz arayüzlü hafif embed (forceHideAll)
    ShortsLightPlayerView(videoId: video.id, shouldPlay: $shouldPlay, showComments: $showComments)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                // Arka planı şeffaf yap: dıştaki bulanık arkaplan kenarlardan görünsün
                Color.clear

                playerEmbed()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 4)
                // Yalnızca video alanına tıklayınca play/pause toggle et (arka siyah boşluk artık tetiklemez)
                .contentShape(Rectangle())
                .onTapGesture {
                        NotificationCenter.default.post(name: .shortsFocusVideoId, object: nil, userInfo: ["videoId": video.id])
                        shouldPlay.toggle()
                    }

                // Sağ aksiyon butonları
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(spacing: actionVerticalSpacing) {
                            // Yukarı
                            if let idx = youtubeAPI.shortsVideos.firstIndex(where: { $0.id == video.id }), idx > 0 {
                                Button(action: {
                                    let prev = idx - 1
                                    if youtubeAPI.shortsVideos.indices.contains(prev) {
                                        NotificationCenter.default.post(name: .shortsFocusVideoId, object: nil, userInfo: ["videoId": youtubeAPI.shortsVideos[prev].id])
                                        NotificationCenter.default.post(name: .shortsRequestPrev, object: nil)
                                    }
                                }) { Image(systemName: "chevron.up.circle.fill").font(.system(size: actionIconSize)) }
                                .buttonStyle(.plain)
                                .foregroundColor(.white)
                            }

                            // Beğeni
                            VStack(spacing: 4) {
                                Image(systemName: "hand.thumbsup").font(.system(size: actionIconSize))
                                Text(youtubeAPI.likeCountByVideoId[video.id] ?? video.likeCount)
                                    .font(.caption).fontWeight(.medium)
                            }
                            .foregroundColor(.white)
                            .onAppear { youtubeAPI.fetchLikeCountIfNeeded(videoId: video.id) }

                            // Yorum
                Button(action: {
                                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { showComments = true }
                                youtubeAPI.fetchComments(videoId: video.id)
                            }) {
                                VStack(spacing: 4) {
                    Image(systemName: "bubble.left").font(.system(size: actionIconSize))
                                    Text(i18n.t(.comment)).font(.caption).fontWeight(.medium)
                                }.foregroundColor(.white)
                            }
                            .buttonStyle(.plain)

                            // Paylaş
                Button(action: { showShareMenu.toggle() }) {
                                VStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: actionIconSize))
                                    Text(i18n.t(.share)).font(.caption).fontWeight(.medium)
                                }.foregroundColor(.white)
                            }
                            .buttonStyle(.plain)
                            .popover(isPresented: $showShareMenu) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(i18n.t(.share)).font(.headline).padding(.bottom, 8)
                                    Button(action: {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString("https://www.youtube.com/shorts/\(video.id)", forType: .string)
                                        showShareMenu = false
                                    }) { HStack { Image(systemName: "doc.on.doc"); Text(i18n.t(.copyLink)) } }
                                    .buttonStyle(.plain)
                                    Button(action: {
                                        if let url = URL(string: "https://www.youtube.com/shorts/\(video.id)") {
                                            NSWorkspace.shared.open(url)
                                        }
                                        showShareMenu = false
                                    }) { HStack { Image(systemName: "play.rectangle"); Text(i18n.t(.openInYouTube)) } }
                                    .buttonStyle(.plain)
                                    Divider()
                                    Button(i18n.t(.cancel)) { showShareMenu = false }
                                        .foregroundColor(.secondary)
                                        .buttonStyle(.plain)
                                }
                                .padding()
                                .frame(width: 200)
                            }

                            // Daha
                Button(action: {}) {
                                VStack(spacing: 4) {
                    Image(systemName: "ellipsis").font(.system(size: actionIconSize))
                                    Text(i18n.t(.more)).font(.caption).fontWeight(.medium)
                                }.foregroundColor(.white)
                            }
                            .buttonStyle(.plain)

                            // Aşağı
                            if let idx = youtubeAPI.shortsVideos.firstIndex(where: { $0.id == video.id }), idx < youtubeAPI.shortsVideos.count - 1 {
                                Button(action: {
                                    let next = idx + 1
                                    if youtubeAPI.shortsVideos.indices.contains(next) {
                                        NotificationCenter.default.post(name: .shortsFocusVideoId, object: nil, userInfo: ["videoId": youtubeAPI.shortsVideos[next].id])
                                        NotificationCenter.default.post(name: .shortsRequestNext, object: nil)
                                    }
                                }) { Image(systemName: "chevron.down.circle.fill").font(.system(size: actionIconSize)) }
                                .buttonStyle(.plain)
                                .foregroundColor(.white)
                            }
                        }
                        .padding(.trailing, actionRightPadding)
                    }
                    .padding(.bottom, actionBottomLift)
                }

                // Alt meta
                VStack {
                    Spacer()
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            AsyncImage(url: URL(string: resolvedThumb.isEmpty ? video.channelThumbnailURL : resolvedThumb)) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: { Circle().fill(Color.gray.opacity(0.5)) }
                            .frame(width: 28, height: 28)
                            .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 4) {
                                Text(video.channelTitle).font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                                // Başlık: her zaman tam metin ("Devamını oku" kaldırıldı)
                                Text(video.title)
                                    .font(.system(size: 15, weight: .regular))
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                        }
                        // Açıklama (video hakkında) bölümü talep üzerine kaldırıldı.
                    }
                    .padding(.horizontal, 12)
                    // Daha yukarı taşımak için bottom padding artırıldı
                    .padding(.bottom, 14 + bottomMetaExtraLift)
                }
            }
            .onAppear {
                if shouldPlay {
                    NotificationCenter.default.post(name: .shortsFocusVideoId, object: nil, userInfo: ["videoId": video.id])
                }
            if video.channelThumbnailURL.isEmpty {
                    Task {
                if let info = await youtubeAPI.quickChannelInfo(channelId: video.channelId), !info.thumbnailURL.isEmpty {
                            await MainActor.run { self.resolvedThumb = info.thumbnailURL }
                        }
                    }
                }
            }
            // Fetch comments when opened from any UI path
            .onChange(of: showComments) { _, opened in
                if opened {
                    youtubeAPI.fetchComments(videoId: video.id)
                }
            }
        }
    }
}

// LightYouTubeEmbed tabanlı Shorts player (compact mod ile paylaşılan)
struct ShortsLightPlayerView: View {
    @EnvironmentObject var i18n: Localizer
    let videoId: String
    @Binding var shouldPlay: Bool
    @Binding var showComments: Bool
    @StateObject private var controller = LightYouTubeController()
    @State private var isReady = false
    @State private var reloadToken = UUID()
    // Center scrubber UI state
    @State private var isScrubbing = false
    @State private var sliderValue: Double = 0
    @State private var lastDuration: Double = 0
    @State private var wasPlayingBeforeScrub = false
    // Volume UI state (top-left)
    @State private var showVolume: Bool = false
    @State private var isVolumeScrubbing: Bool = false
    @State private var volumePercent: Double = 80 // 0...100 (restored from persisted value if exists)
    @State private var volumeHideWorkItem: DispatchWorkItem? = nil
    // Repeat control state (top-right)
    private enum RepeatMode: String { case off, once, infinite }
    @State private var repeatMode: RepeatMode = .off // restored from persisted value if exists
    // Gate to avoid firing replay more than once near the tail
    @State private var repeatArm: Bool = true

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let s = Int(seconds.rounded())
        let m = s / 60
        let r = s % 60
        return String(format: "%d:%02d", m, r)
    }

    var body: some View {
        ZStack {
            LightYouTubeEmbed(
                videoId: videoId,
                startSeconds: 0,
                autoplay: shouldPlay,
                forceHideAll: true,
                showOnlyProgressBar: false,
                applyAppearanceSettings: false,
                initialVolumePercent: Int(volumePercent),
                controller: controller,
                onReady: { withAnimation(.easeOut(duration: 0.18)) { isReady = true } },
                disableContextMenu: true
            )
            .id(reloadToken)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            // Right-clicks are forwarded by PassthroughWKWebView so SwiftUI .contextMenu can appear
            // Custom context menu for Shorts
            .contextMenu {
                // 1) Play/Pause toggle depending on state
                Button(action: {
                    if shouldPlay { controller.pause() } else { controller.play() }
                    shouldPlay.toggle()
                }) {
                    Label(shouldPlay ? i18n.t(.pause) : i18n.t(.play), systemImage: shouldPlay ? "pause.fill" : "play.fill")
                }

                // 2) Show/Hide comments
                Button(action: {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                        showComments.toggle()
                    }
                    // If opening, request load (parent also listens via onChange as safety)
                    if showComments {
                        NotificationCenter.default.post(name: .userInteractedWithShorts, object: nil)
                    }
                }) {
                    Label(showComments ? i18n.t(.hideComments) : i18n.t(.showComments), systemImage: "text.bubble")
                }

                // 3) Copy link
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("https://www.youtube.com/shorts/\(videoId)", forType: .string)
                }) {
                    Label(i18n.t(.copyLink), systemImage: "doc.on.doc")
                }
            }
            // Yükleme sırasında görünen overlay de aynı köşeli maske ile kliplensin
            if !isReady {
                Color.black.opacity(0.6)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(ProgressView())
            }
            // Center scrubber overlay
            GeometryReader { g in
                // Only show when duration known (>0)
                if (lastDuration > 0) || (controller.duration > 0) {
                    let dur = lastDuration > 0 ? lastDuration : controller.duration
                    VStack(spacing: 6) {
                        HStack(spacing: 10) {
                            Text(formatTime(isScrubbing ? sliderValue : controller.lastKnownTime))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white.opacity(0.95))
                                .monospacedDigit()
                            Slider(value: Binding<Double>(
                                get: { isScrubbing ? sliderValue : min(max(0, controller.lastKnownTime), dur) },
                                set: { sliderValue = $0 }
                            ), in: 0...max(1, dur), onEditingChanged: { editing in
                                if editing {
                                    // begin
                                    isScrubbing = true
                                    wasPlayingBeforeScrub = shouldPlay
                                    controller.pause()
                                } else {
                                    // end
                                    let target = sliderValue
                                    controller.seek(to: target)
                                    isScrubbing = false
                                    if wasPlayingBeforeScrub { controller.play() }
                                }
                            })
                            .tint(.red)
                            .frame(maxWidth: .infinity)
                            Text(formatTime(dur))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white.opacity(0.9))
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 2)
                        .frame(width: min(g.size.width * 0.9, 680))
                    }
                    // Place scrubber at the absolute bottom (tiny safe margin for rounded corners)
                    .position(x: g.size.width/2, y: max(32, g.size.height - 28))
                }
            }

            // Top-left volume control overlay
            VStack {
                HStack(spacing: 8) {
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                            showVolume.toggle()
                        }
                        if showVolume { scheduleHideVolume() }
                    }) {
                        Image(systemName: volumeIconName(volumePercent))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)

                    if showVolume {
                        HStack(spacing: 8) {
                            Slider(value: $volumePercent, in: 0...100, onEditingChanged: { editing in
                                isVolumeScrubbing = editing
                                if !editing { scheduleHideVolume() }
                            })
                            .frame(width: 120)
                            .tint(.red)
                        }
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 2)
                .padding(.top, 12)
                .padding(.leading, 12)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // Top-right repeat control overlay
            VStack {
                HStack(spacing: 8) {
                    Button(action: { cycleRepeatMode() }) {
                        ZStack(alignment: .topTrailing) {
                            // Base glyph is always the repeat icon
                            Image(systemName: "repeat")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(repeatIconColor())
                                .frame(width: 20, height: 20)
                            // Overlay state badge: 1 for Once, ∞ for Infinite
                            switch repeatMode {
                            case .once:
                                Text("1")
                                    .font(.system(size: 8, weight: .heavy))
                                    .foregroundColor(.white)
                                    .offset(x: 3, y: -3)
                                    .accessibilityHidden(true)
                            case .infinite:
                                Image(systemName: "infinity")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundColor(.white)
                                    .offset(x: 3, y: -3)
                                    .accessibilityHidden(true)
                            case .off:
                                EmptyView()
                            }
                        }
                    }
                    .accessibilityLabel({
                        switch repeatMode {
                        case .off: return Text("Repeat: Off")
                        case .once: return Text("Repeat: Once")
                        case .infinite: return Text("Repeat: Infinite")
                        }
                    }())
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 2)
                .padding(.top, 12)
                .padding(.trailing, 12)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        // Tüm katmanları güvenli olması için tekrar kliple
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        // Restore persisted settings for Shorts controls when this view appears
        .onAppear {
            // Volume (restore even if muted = 0)
            if let obj = UserDefaults.standard.object(forKey: "ShortsVolumePercent") as? NSNumber {
                let v = obj.doubleValue
                volumePercent = max(0, min(v, 100))
            }
            // Repeat mode
            if let raw = UserDefaults.standard.string(forKey: "ShortsRepeatMode"), let m = RepeatMode(rawValue: raw) {
                repeatMode = m
            }
        }
        .onChange(of: shouldPlay) { _, play in
            Task { @MainActor in
                if play {
                    if controller.isDestroyed {
                        isReady = false
                        reloadToken = UUID()
                    } else {
                        controller.play()
                    }
                } else { controller.pause() }
            }
        }
        .onChange(of: videoId) { _, _ in
            isReady = false
        }
        .onChange(of: isReady) { _, ready in
            if ready {
                controller.setVolume(percent: Int(volumePercent))
            }
        }
        // Keep local mirrors for duration/slider sync
        .onChange(of: controller.duration) { _, d in
            lastDuration = d
        }
        .onChange(of: controller.lastKnownTime) { _, t in
            if !isScrubbing { sliderValue = t }
            // Arm repeat while we're clearly before the tail
            if lastDuration > 2, t < max(0, lastDuration - 1.2) { repeatArm = true }
            // Fallback tail trigger: if repeat is active and we cross into the tail window, replay even if 'ended' doesn't arrive
            if repeatArm, lastDuration > 2, t >= max(0, lastDuration - 0.4) {
                switch repeatMode {
                case .off: break
                case .once:
                    repeatArm = false
                    controller.seek(to: 0)
                    controller.play()
                    repeatMode = .off
                case .infinite:
                    repeatArm = false
                    controller.seek(to: 0)
                    controller.play()
                }
            }
        }
        .onChange(of: volumePercent) { _, newVal in
            controller.setVolume(percent: Int(newVal))
            if showVolume && !isVolumeScrubbing { scheduleHideVolume() }
            // Persist Shorts volume
            UserDefaults.standard.set(newVal, forKey: "ShortsVolumePercent")
        }
        // Persist repeat mode when it changes
        .onChange(of: repeatMode) { _, m in
            UserDefaults.standard.set(m.rawValue, forKey: "ShortsRepeatMode")
        }
        // React to player state like playlist player does
        .onChange(of: controller.playerState) { _, state in
            let dur = lastDuration > 0 ? lastDuration : controller.duration
            let nearEnd = (dur > 2) && (controller.lastKnownTime >= max(0, dur - 0.6))
            if state == 0 || (state == 2 && nearEnd) { // ended (or effectively ended)
                switch repeatMode {
                case .off:
                    break
                case .once:
                    controller.seek(to: 0)
                    controller.play()
                    repeatMode = .off
                case .infinite:
                    controller.seek(to: 0)
                    controller.play()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .shortsResetVideoId)) { note in
            guard let target = note.userInfo?["videoId"] as? String, target == videoId else { return }
            Task { @MainActor in
                controller.pause()
                controller.destroy()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .shortsStopAll)) { _ in
            Task { @MainActor in
                controller.pause()
                controller.destroy()
            }
        }
        // Global stop for any video embeds if needed
        .onReceive(NotificationCenter.default.publisher(for: .stopAllVideos)) { _ in
            Task { @MainActor in
                controller.pause()
                controller.destroy()
            }
        }
        .onDisappear {
            Task { @MainActor in
                controller.pause()
                controller.destroy()
            }
        }
    }
}

// MARK: - Volume helpers
private extension ShortsLightPlayerView {
    // Repeat helpers
    func repeatIconName() -> String { "repeat" }
    func repeatIconColor() -> Color {
        switch repeatMode {
        case .off: return .white.opacity(0.6)
        case .once, .infinite: return .white
        }
    }
    func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .once
        case .once: repeatMode = .infinite
        case .infinite: repeatMode = .off
        }
        // Reset arm so next tail crossing can trigger
        repeatArm = true
    }
    func volumeIconName(_ vol: Double) -> String {
        if vol <= 0 { return "speaker.slash.fill" }
        if vol < 34 { return "speaker.fill" }
        if vol < 67 { return "speaker.wave.1.fill" }
        return "speaker.wave.2.fill"
    }
    func scheduleHideVolume(after seconds: Double = 2.2) {
        volumeHideWorkItem?.cancel()
        let work = DispatchWorkItem {
            if !isVolumeScrubbing {
                withAnimation(.easeOut(duration: 0.15)) { showVolume = false }
            }
        }
        volumeHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}

// MARK: - Helpers to swallow right-clicks
private struct GestureDetectorView: NSViewRepresentable {
    let onRightClick: () -> Void
    func makeNSView(context: Context) -> NSView {
        return RightClickSwallowView(onRightClick: onRightClick)
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    private final class RightClickSwallowView: NSView {
        let onRightClick: () -> Void
        init(onRightClick: @escaping () -> Void) { self.onRightClick = onRightClick; super.init(frame: .zero) }
        @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            // Forward primary clicks to allow higher-level SwiftUI gestures (play/pause toggles)
            nextResponder?.mouseDown(with: event)
        }
        override func rightMouseDown(with event: NSEvent) { onRightClick() /* swallow */ }
        override func otherMouseDown(with event: NSEvent) { onRightClick() /* swallow */ }
        override func menu(for event: NSEvent) -> NSMenu? { nil }
    }
}
