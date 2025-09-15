/*
 File Overview (EN)
 Purpose: Reusable shimmer/skeleton loading effect for placeholders while content is loading.
 Key Responsibilities:
 - Provide animated gradient shimmer overlay
 - Easy-to-apply modifier-style API for views
 Used By: Video cards, list rows, and stats while fetching.

 Dosya Özeti (TR)
 Amacı: İçerik yüklenirken iskelet/şeritli yükleme efekti sağlayan yeniden kullanılabilir bileşen.
 Ana Sorumluluklar:
 - Animasyonlu degrade shimmer kaplaması sunmak
 - Görünümlere kolayca uygulanabilir modifier tarzı API sağlamak
 Nerede Kullanılır: Video kartları, liste satırları ve istatistik alanları.
*/

import SwiftUI

// Shimmer Effect Extension
extension View {
    func shimmering() -> some View {
        modifier(ShimmerModifier())
    }
}

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.white.opacity(0.4),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .rotationEffect(.degrees(30))
                    .offset(x: phase)
                    .clipped()
            )
            .onAppear {
                withAnimation(
                    Animation.linear(duration: 1.5)
                        .repeatForever(autoreverses: false)
                ) {
                    phase = 400
                }
            }
    }
}
