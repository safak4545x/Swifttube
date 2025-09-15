/*
 File Overview (EN)
 Purpose: Off-screen hidden player surface used for background audio playback and smooth handovers to mini player.
 Key Responsibilities:
 - Keep an audio-only session alive when UI player isn’t visible
 - Coordinate start/stop with mini player and overlay transitions
 - Expose simple controls via Notifications or bindings
 Used By: Background audio and mini player resume logic.

 Dosya Özeti (TR)
 Amacı: Arka planda ses çalma ve mini oynatıcıya yumuşak geçişler için kullanılan ekran dışı gizli oynatıcı yüzeyi.
 Ana Sorumluluklar:
 - UI oynatıcı görünmüyorken yalnızca ses oturumunu canlı tutmak
 - Başlat/durdur işlemlerini mini oynatıcı ve overlay geçişleriyle koordine etmek
 - Bildirimler veya binding’ler aracılığıyla basit kontroller sağlamak
 Nerede Kullanılır: Arka plan ses çalma ve mini oynatıcıya devam etme mantığı.
*/

import SwiftUI

/// A hidden WebView host for audio-only playback using LightYouTubeEmbed.
/// Renders at 1x1 size and with forceHideAll; attached to the main view tree so media keeps playing.
struct HiddenAudioPlayerView: View {
    @ObservedObject var audio: AudioPlaylistPlayer
    @State private var readyToken: UUID = UUID()

    var body: some View {
        Group {
            if audio.isActive, let vid = audio.currentVideoId {
                LightYouTubeEmbed(
                    videoId: vid,
                    startSeconds: 0,
                    autoplay: audio.isPlaying,
                    forceHideAll: true, // hide all UI and visuals
                    showOnlyProgressBar: false,
                    applyAppearanceSettings: false,
                    enableColorSampling: false,
                    controller: audio.controller,
                    onReady: {}
                )
                // Render extremely small and fully transparent
                .frame(width: 1, height: 1)
                .opacity(0.001) // keep in hierarchy but visually invisible
                .accessibilityHidden(true)
                .id(readyToken)
                .onChange(of: audio.currentVideoId) { _, _ in
                    // In-place switch when possible to avoid destroying the webview
                    if let vid = audio.currentVideoId { audio.controller.load(videoId: vid, autoplay: audio.isPlaying) }
                    // Nudge duration/time to refresh after a small delay so mini bar updates immediately
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        audio.controller.fetchDuration { _ in }
                    }
                }
                .onChange(of: audio.isPlaying) { _, playing in
                    if playing { audio.controller.play() } else { audio.controller.pause() }
                }
                .onAppear {
                    audio.controller.setVolume(percent: Int(audio.volume * 100))
                }
                .onChange(of: audio.volume) { _, v in
                    audio.controller.setVolume(percent: Int(v * 100))
                }
            } else {
                Color.clear.frame(width: 1, height: 1).opacity(0.0)
            }
        }
        .frame(width: 1, height: 1)
        .clipped()
    }
}
