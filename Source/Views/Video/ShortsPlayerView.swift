/*
 File Overview (EN)
 Purpose: Vertical Shorts player with mute/repeat controls, comment toggling, and overlay menu integration.
 Key Responsibilities:
 - Drive play/stop on focus changes; persist per-video volume/mute
 - Show retry/cached thumbnails and reduce system context menu interference
 - Emit navigation requests (next/prev) via Notifications
 Used By: ShortsView list and full-height single Shorts playback.

 Dosya Özeti (TR)
 Amacı: Sessiz/tekrar kontrolleri, yorum aç/kapat ve overlay menü entegrasyonu olan dikey Shorts oynatıcısı.
 Ana Sorumluluklar:
 - Odak değişimlerinde oynat/durdur; video başına ses/dilsiz durumunu kalıcı kılmak
 - Sistem bağlam menüsü etkisini azaltmak; yeniden dene/önbellekli küçük görselleri göstermek
 - Bildirimler ile ileri/geri gezinme istekleri yaymak
 Nerede Kullanılır: ShortsView listesi ve tam yükseklikte tek Shorts oynatma.
*/

import SwiftUI
import YouTubePlayerKit

// Shorts-specific player using YouTubePlayerKit (separate lifecycle & future customization)
struct ShortsPlayerView: View {
    let videoId: String
    @Binding var shouldPlay: Bool

    @State private var reloadToken = UUID()
    @State private var player: YouTubePlayer
    @State private var isReady = false
    @State private var destroyed = false

    init(videoId: String, shouldPlay: Binding<Bool>) {
        self.videoId = videoId
        self._shouldPlay = shouldPlay
        // Minimal UI: kontrol barı & fullscreen butonu gizle, klavye kısayollarını kapat, ilgili videoları aynı kanalla sınırla
        let ytParams = YouTubePlayer.Parameters(
            autoPlay: false, // manuel play kontrolü (safePlay) ile senkronize ediyoruz
            showControls: false,
            showFullscreenButton: false,
            keyboardControlsDisabled: true,
            restrictRelatedVideosToSameChannel: true
        )
        _player = State(initialValue: YouTubePlayer(
            source: .video(id: videoId),
            parameters: ytParams
        ))
    }

    var body: some View {
    YouTubePlayerView(player) { state in
            // State overlay (progress / error). Keep minimal to emphasize video.
            switch state {
            case .idle:
                ZStack { Color.black; ProgressView() }
            case .ready:
                Color.clear.onAppear {
                    if !isReady {
                        isReady = true
                        if shouldPlay { Task { await safePlay() } }
                    }
                }
            case .error:
                ZStack { Color.black; Image(systemName: "exclamationmark.triangle").foregroundColor(.yellow) }
            default:
                Color.clear
            }
    }
        .id(reloadToken)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onChange(of: shouldPlay) { _, play in
            if destroyed {
                if play { recreatePlayer(autoplay: true) }
                return
            }
            Task { @MainActor in
                if play { await safePlay() } else { await safePause() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .shortsResetVideoId)) { note in
            guard let target = note.userInfo?["videoId"] as? String, target == videoId else { return }
            destroyPlayer()
        }
        .onReceive(NotificationCenter.default.publisher(for: .shortsStopAll)) { _ in
            destroyPlayer()
        }
    }

    @MainActor private func safePlay() async { try? await player.play() }
    @MainActor private func safePause() async { try? await player.pause() }

    private func destroyPlayer() {
        guard !destroyed else { return }
        Task { await safePause() }
        destroyed = true
        isReady = false
    // Replace with an inert player (no source) so underlying WebView can release resources
    player = YouTubePlayer() // source: nil
        reloadToken = UUID()
    }

    private func recreatePlayer(autoplay: Bool) {
        let ytParams = YouTubePlayer.Parameters(
            autoPlay: false,
            showControls: false,
            showFullscreenButton: false,
            keyboardControlsDisabled: true,
            restrictRelatedVideosToSameChannel: true
        )
        player = YouTubePlayer(
            source: .video(id: videoId),
            parameters: ytParams
        )
        destroyed = false
        isReady = false
        reloadToken = UUID()
        if autoplay {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 120_000_000)
                await safePlay()
            }
        }
    }
}
