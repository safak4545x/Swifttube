
/*
 File Overview (EN)
 Purpose: Adapter/wrapper that embeds ChannelView with required environment and bindings from parent contexts.
 Key Responsibilities:
 - Bridge environment objects and callbacks into ChannelView
 - Simplify usage in sheets/overlays
 Used By: SheetManagementView and panels that show channel details.

 Dosya Özeti (TR)
 Amacı: ChannelView'i üst bağlamlardan gelen ortam ve binding’lerle birlikte saran adaptör.
 Ana Sorumluluklar:
 - Ortam nesneleri ve geri çağrıları ChannelView'e köprülemek
 - Sheet/overlay içinde kullanımı basitleştirmek
 Nerede Kullanılır: Kanal detay panelini gösteren sheet/panel bileşenlerinde.
*/

import SwiftUI

// Kanal sayfası wrapper - responsive sheet tasarımı
struct ChannelViewWrapper: View {
    let channel: YouTubeChannel
    @ObservedObject var youtubeAPI: YouTubeAPIService
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Arka plan
            Color(.windowBackgroundColor)
                .edgesIgnoringSafeArea(.all)
            
            // Kanal içeriği - video paneli ile aynı strateji
            ChannelView(channel: channel, youtubeAPI: youtubeAPI)
            
            // Kapatma butonu - video panelindeki ile tamamen aynı
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
