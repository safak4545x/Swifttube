/*
 File Overview (EN)
 Purpose: Ambient blurred background effect around the video player, derived from sampled frame colors.
 Key Responsibilities:
 - Sample colors from the player and generate a subtle blurred backdrop
 - Animate appearance/disappearance and respond to theme changes
 - Remain lightweight so it doesn’t affect playback performance
 Used By: VideoEmbedView and related player surfaces.

 Dosya Özeti (TR)
 Amacı: Oyuncu etrafında, örneklenen kare renklerinden türetilen ortam bulanık arka plan efekti.
 Ana Sorumluluklar:
 - Oynatıcıdan renk örnekleyip yumuşak bulanık arka plan üretmek
 - Görünümün açılıp kapanmasını canlandırmak ve tema değişikliklerine tepki vermek
 - Oynatma performansını etkilemeyecek kadar hafif kalmak
 Nerede Kullanılır: VideoEmbedView ve ilgili oynatıcı yüzeyleri.
*/

import SwiftUI

// Shorts tarzı çevresel blur'u sadece video çerçevesinin etrafında göstermek için yardımcı view
struct AmbientBlurAroundPlayer: View {
    let urlString: String
    var cornerRadius: CGFloat = 12
    // Blur'un çerçeveden ne kadar dışarı taşacağını belirler
    var spread: CGFloat = 180
    // Dinamik renk (video karesinden) verildiğinde, üzerine yumuşak bir renk overlay uygular
    var dynamicTint: Color? = nil

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let expandedW = w + spread * 2
            let expandedH = h + spread * 2

            CachedAsyncImage(url: URL(string: urlString)) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: expandedW, height: expandedH)
                    .clipped()
                    .blur(radius: 50)
                    .saturation(0.95)
                    .overlay(
                        ZStack {
                            if let tint = dynamicTint {
                                tint.opacity(0.35)
                                    .transition(.opacity)
                                    .animation(.easeInOut(duration: 0.35), value: dynamicTint)
                            }
                            Color.black.opacity(0.2)
                        }
                    )
                    .mask(
                        // Yalnızca video çerçevesinin etrafında yumuşak bir hale oluştur
                        RoundedRectangle(cornerRadius: cornerRadius + 8, style: .continuous)
                            .fill(Color.white)
                            .frame(width: w + spread, height: h + spread)
                            .blur(radius: 65) // kenarlara doğru yumuşak geçiş
                    )
                    .offset(x: -spread, y: -spread) // genişlettiğimiz alanı merkeze hizala
            } placeholder: {
                Color.clear
            }
        }
        .allowsHitTesting(false)
    }
}
