/*
 File Overview (EN)
 Purpose: Collection of common overlay components such as loading and error views used across pages.
 Key Responsibilities:
 - Provide LoadingOverlayView and ErrorOverlayView with consistent styling
 - Reusable building blocks for temporary full-screen overlays
 Used By: MainContentView and other pages during fetch states.

 Dosya Özeti (TR)
 Amacı: Sayfalar genelinde kullanılan yükleme ve hata gibi ortak overlay bileşenlerinin toplamı.
 Ana Sorumluluklar:
 - Tutarlı stillerde LoadingOverlayView ve ErrorOverlayView sunmak
 - Geçici tam ekran overlay'ler için yeniden kullanılabilir yapı taşları sağlamak
 Nerede Kullanılır: MainContentView ve diğer sayfalarda veri çekme sırasında.
*/

import SwiftUI

struct LoadingOverlayView: View {
    @EnvironmentObject var i18n: Localizer
    var body: some View {
        VStack {
            ProgressView()
                .scaleEffect(1.5)
            Text(i18n.t(.videosLoading))
                .foregroundColor(.secondary)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
    }
}

struct ErrorOverlayView: View {
    @EnvironmentObject var i18n: Localizer
    let error: String
    
    var body: some View {
        VStack {
        Text(i18n.t(.errorLabel))
                .font(.headline)
                .foregroundColor(.red)
            Text(error)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }
}
    
