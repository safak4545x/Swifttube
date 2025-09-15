/*
 Overview / Genel Bakış
 EN: Ambient blurred backdrop around the player, tinted by sampled frame colors; lightweight and purely visual.
 TR: Oynatıcı etrafında, kare renklerinden tonlanan hafif bir bulanık arka plan; yalnızca görsel amaçlı ve hafif.
*/

// EN: SwiftUI imports for view composition. TR: Görünüm bileşimi için SwiftUI içe aktarımları.
import SwiftUI

// EN: Helper view that renders a soft ambient blur around the video frame. TR: Video çerçevesinin etrafında yumuşak bir çevresel blur oluşturan yardımcı görünüm.
struct AmbientBlurAroundPlayer: View {
    let urlString: String
    var cornerRadius: CGFloat = 12
    // EN: How far the blur extends beyond the frame. TR: Blur’un çerçevenin dışına ne kadar taşacağı.
    var spread: CGFloat = 180
    // EN: Optional dynamic tint derived from sampled frame colors. TR: Örneklenen kare renklerinden türetilebilen isteğe bağlı dinamik tonlama.
    var dynamicTint: Color? = nil

    var body: some View {
        // EN: Expand and blur an image, then mask to a rounded shape around the player. TR: Görseli genişletip blur uygular, sonra oynatıcı çevresinde yuvarlatılmış bir şekille maske uygular.
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
                    // EN: Heavy blur to create soft ambient glow. TR: Yumuşak çevresel parıltı için güçlü blur.
                    .blur(radius: 50)
                    .saturation(0.95)
                    .overlay(
                        ZStack {
                            // EN: Apply dynamic tint if provided. TR: Varsa dinamik tonu uygula.
                            if let tint = dynamicTint {
                                tint.opacity(0.35)
                                    .transition(.opacity)
                                    .animation(.easeInOut(duration: 0.35), value: dynamicTint)
                            }
                            // EN: Subtle darkening to prevent washed-out look. TR: Soluk görünümü engellemek için hafif karartma.
                            Color.black.opacity(0.2)
                        }
                    )
                    .mask(
                        // EN: Soft halo mask around player area. TR: Oynatıcı alanı etrafında yumuşak hale maskesi.
                        RoundedRectangle(cornerRadius: cornerRadius + 8, style: .continuous)
                            .fill(Color.white)
                            .frame(width: w + spread, height: h + spread)
                            .blur(radius: 65) // EN: Feathered edges. TR: Kenarlara doğru yumuşama.
                    )
                    .offset(x: -spread, y: -spread) // EN: Recenter oversized layer. TR: Büyütülmüş katmanı tekrar ortala.
            } placeholder: {
                Color.clear
            }
        }
        .allowsHitTesting(false)
    }
}
