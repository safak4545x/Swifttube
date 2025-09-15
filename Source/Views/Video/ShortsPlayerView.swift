/*
 Overview / Genel Bakış
 EN: Vertical Shorts player with focus-driven play/pause and simple lifecycle; integrates with notifications.
 TR: Odakla tetiklenen oynat/duraklat ve basit yaşam döngüsü olan dikey Shorts oynatıcı; bildirimlerle entegre.
*/

// EN: SwiftUI + YouTubePlayerKit for a dedicated Shorts player. TR: Shorts oynatıcı için SwiftUI + YouTubePlayerKit.
import SwiftUI
import YouTubePlayerKit

// EN: Shorts-specific player using YouTubePlayerKit (separate lifecycle). TR: YouTubePlayerKit tabanlı Shorts oynatıcı (ayrı yaşam döngüsü).
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
        // EN: Minimal UI (no controls/fullscreen, disabled keyboard, related limited to same channel). TR: Minimal arayüz (kontrol/fullscreen yok, klavye kapalı, ilgili videolar aynı kanal).
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
        // EN: Render state overlays while the underlying player initializes. TR: Oynatıcı başlarken durum katmanlarını göster.
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
        // EN: External focus toggles playback. TR: Harici odak değişimi oynatmayı değiştirir.
        .onChange(of: shouldPlay) { _, play in
            if destroyed {
                if play { recreatePlayer(autoplay: true) }
                return
            }
            Task { @MainActor in
                if play { await safePlay() } else { await safePause() }
            }
        }
        // EN: Reset/destroy from global events. TR: Global olaylarla sıfırla/yok et.
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
        // EN: Swap to an inert player to let the WebView release resources. TR: WebView kaynaklarını bırakabilsin diye etkisiz oynatıcıya geç.
        player = YouTubePlayer() // source: nil
        reloadToken = UUID()
    }

    private func recreatePlayer(autoplay: Bool) {
        // EN: Recreate player with same params; optionally auto-play after a short delay. TR: Aynı parametrelerle oyuncuyu yeniden yarat; isteğe bağlı kısa gecikme ile otomatik oynat.
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
