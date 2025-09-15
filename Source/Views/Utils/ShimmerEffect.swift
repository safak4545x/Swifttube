/*
 Overview / Genel Bakış
 EN: Reusable shimmer/skeleton loading effect as a view modifier.
 TR: Görünüm değiştiricisi olarak yeniden kullanılabilir shimmer/iskelet efekti.
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
                    phase = 400 // EN: Sweep across horizontally. TR: Yatay tarama mesafesi.
                }
            }
    }
}
