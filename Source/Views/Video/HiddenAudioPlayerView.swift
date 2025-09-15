/*
 Overview / Genel Bakış
 EN: Hidden, off-screen player host for background audio and mini-player handoffs.
 TR: Arka plan ses ve mini oynatıcı geçişleri için gizli, ekran dışı oynatıcı yüzeyi.
*/

// EN: SwiftUI for embedding a nearly invisible player. TR: Neredeyse görünmez oynatıcı gömmek için SwiftUI.
import SwiftUI

/// EN: Hidden LightYouTubeEmbed host for audio-only playback; remains in the tree to keep media alive.
/// TR: Ses odaklı oynatma için gizli LightYouTubeEmbed; medya akışını sürdürmek için hiyerarşide kalır.
struct HiddenAudioPlayerView: View {
    @ObservedObject var audio: AudioPlaylistPlayer
    @State private var readyToken: UUID = UUID()

    var body: some View {
        Group {
            // EN: Only attach the webview when audio session is active. TR: Webview’i yalnızca ses oturumu aktifken ekle.
            if audio.isActive, let vid = audio.currentVideoId {
                LightYouTubeEmbed(
                    videoId: vid,
                    startSeconds: 0,
                    autoplay: audio.isPlaying,
                    forceHideAll: true, // EN: Hide all UI and visuals; audio only. TR: Tüm UI/görseller gizli; sadece ses.
                    showOnlyProgressBar: false,
                    applyAppearanceSettings: false,
                    enableColorSampling: false,
                    controller: audio.controller,
                    onReady: {}
                )
                // EN: Render at 1x1 and nearly transparent to avoid layout impact. TR: Yerleşimi etkilememek için 1x1 boyutta ve neredeyse tamamen saydam render et.
                .frame(width: 1, height: 1)
                .opacity(0.001) // keep in hierarchy but visually invisible
                .accessibilityHidden(true)
                .id(readyToken)
                .onChange(of: audio.currentVideoId) { _, _ in
                    // EN: In-place switch to avoid destroying the webview. TR: Webview’i yok etmeden yerinde geçiş yap.
                    if let vid = audio.currentVideoId { audio.controller.load(videoId: vid, autoplay: audio.isPlaying) }
                    // EN: Nudge duration fetch shortly after to update mini bar state. TR: Mini çubuğun hemen güncellenmesi için kısa süre sonra süre bilgisini tetikle.
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
