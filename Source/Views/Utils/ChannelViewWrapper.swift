
/*
 Overview / Genel Bakış
 EN: Thin wrapper to show ChannelView in sheets/overlays with proper environment.
 TR: ChannelView'i sheet/overlay içinde doğru ortamla sunan ince sarmalayıcı.
*/

import SwiftUI

// Kanal sayfası wrapper - responsive sheet tasarımı
struct ChannelViewWrapper: View {
    let channel: YouTubeChannel
    @ObservedObject var youtubeAPI: YouTubeAPIService
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // EN: Overlay background. TR: Overlay arka planı.
            Color(.windowBackgroundColor)
                .edgesIgnoringSafeArea(.all)
            
            // EN: Main channel content, mirroring the video panel strategy. TR: Kanal içeriği, video panel stratejisiyle aynı.
            ChannelView(channel: channel, youtubeAPI: youtubeAPI)
            
            // EN: Close button, consistent with video panel. TR: Video paneliyle tutarlı kapatma düğmesi.
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
                    .background(Color(.windowBackgroundColor).opacity(0.8))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .padding(.trailing, 8)
        }
        .background(Color(.windowBackgroundColor))
    }
}
