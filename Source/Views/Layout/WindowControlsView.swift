/*
 Overview / Genel Bakış
 EN: Custom header strip with reserved area for native macOS traffic lights and a sidebar toggle.
 TR: Yerel macOS trafik ışıkları için ayrılmış alan ve kenar çubuğu anahtarı içeren özel başlık şeridi.
*/

// EN: SwiftUI host for custom titlebar controls. TR: Özel başlık çubuğu kontrolleri için SwiftUI.
import SwiftUI

// EN: Shows reserved space and a sidebar toggle button. TR: Ayrılmış alan ve kenar çubuğu anahtarını gösterir.
struct WindowControlsView: View {
    // EN: Shared sidebar state for toggling visibility. TR: Görünürlüğü değiştirmek için paylaşılan kenar çubuğu durumu.
    @ObservedObject var sidebarState: SidebarState
    
    var body: some View {
        HStack {
            // EN: Reserved area for the window traffic lights. TR: Pencere trafik ışıkları için ayrılmış alan.
            Spacer()
                .frame(width: 80) // EN: Reserve horizontal space. TR: Yatay alan ayır.
            
            // EN: Sidebar toggle button with animation. TR: Animasyonlu kenar çubuğu anahtar butonu.
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
            .help("Toggle Sidebar") // EN: Tooltip for accessibility. TR: Erişilebilirlik için ipucu.
            
            Spacer()
        }
        .frame(height: 28) // EN: Compact title strip height. TR: Kompakt başlık şeridi yüksekliği.
        .background(
            // EN: Native titlebar material for visual consistency. TR: Görsel tutarlılık için yerel başlık materyali.
            VisualEffectView(material: .titlebar, blendingMode: .behindWindow)
        )
    }
}
