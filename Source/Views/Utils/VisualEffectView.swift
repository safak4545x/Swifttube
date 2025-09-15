import AppKit
/*
 Overview / Genel Bakış
 EN: SwiftUI wrapper for NSVisualEffectView to get native macOS blur/vibrancy.
 TR: Yerel macOS blur/canlılık için NSVisualEffectView sarmalayıcısı.
*/

import SwiftUI

// Şeffaf arka plan için NSVisualEffectView
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    init(
        material: NSVisualEffectView.Material = .sidebar,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    ) {
        self.material = material
        self.blendingMode = blendingMode
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active // EN: Keep effect active regardless of window focus. TR: Pencere odağından bağımsız aktif tut.
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
