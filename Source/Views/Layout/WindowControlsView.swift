
/*
 File Overview (EN)
 Purpose: Custom window control buttons (close/minimize/zoom) styled to match the app, typically used in custom title/header areas.
 Key Responsibilities:
 - Render macOS-like traffic light controls in SwiftUI
 - Provide hover/tint behaviors consistent with app theme
 Used By: Header/toolbar areas where default titlebar is customized.

 Dosya Özeti (TR)
 Amacı: Uygulama temasına uygun özelleştirilmiş pencere kontrol butonları (kapat/küçült/büyüt); genellikle başlık/üst bölgelerde kullanılır.
 Ana Sorumluluklar:
 - SwiftUI ile macOS trafik ışığı kontrollerini çizmek
 - Uygulama temasıyla uyumlu hover/renk davranışları sağlamak
 Nerede Kullanılır: Varsayılan başlık çubuğunun özelleştirildiği header/toolbar alanları.
*/

import SwiftUI

struct WindowControlsView: View {
    @ObservedObject var sidebarState: SidebarState
    
    var body: some View {
        HStack {
            // Apple'ın native traffic lights için alan - otomatik olarak görünecek
            Spacer()
                .frame(width: 80) // Native traffic lights için reserved space
            
            // Sidebar toggle button - Apple style
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    sidebarState.toggle()
                }
            }) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
            }
            .buttonStyle(.plain)
            .help("Toggle Sidebar")
            
            Spacer()
        }
        .frame(height: 28)
        .background(
            // Native titlebar material
            VisualEffectView(material: .titlebar, blendingMode: .behindWindow)
        )
    }
}
