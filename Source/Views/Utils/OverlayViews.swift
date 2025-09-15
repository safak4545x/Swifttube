/*
 Overview / Genel Bakış
 EN: Common loading and error overlays with consistent styling.
 TR: Tutarlı stilli ortak yükleme ve hata overlay'leri.
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
        .background(Color(NSColor.controlBackgroundColor).opacity(0.8)) // EN: Dimmed backdrop. TR: Kısık arkaplan.
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
        .background(Color(NSColor.controlBackgroundColor)) // EN: Solid backdrop to emphasize error. TR: Hata vurgusu için düz arkaplan.
    }
}
    
