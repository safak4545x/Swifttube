
import AppKit
/*
 File Overview (EN)
 Purpose: NSVisualEffectView wrapper for SwiftUI, enabling macOS vibrancy/blur materials within SwiftUI views.
 Key Responsibilities:
 - Bridge AppKit NSVisualEffectView into SwiftUI
 - Expose material and blending mode configuration
 Used By: Overlays, headers, and buttons needing native blur.

 Dosya Özeti (TR)
 Amacı: SwiftUI içinde macOS canlılık/blur efektlerini kullanmak için NSVisualEffectView sarmalayıcısı.
 Ana Sorumluluklar:
 - AppKit NSVisualEffectView'i SwiftUI'ye köprülemek
 - Materyal ve karıştırma modu ayarlarını dışa açmak
 Nerede Kullanılır: Blur gereken overlay, başlık ve buton arkaplanlarında.
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
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
