/*
 File Overview (EN)
 Purpose: Observable state for the sidebar, including visibility and selection-related toggles.
 Key Responsibilities:
 - Track sidebar visibility and expose a simple toggle
 - Provide lightweight UI state decoupled from network/services
 Used By: MainContentView and SidebarView.

 Dosya Özeti (TR)
 Amacı: Yandan menünün görünürlüğü ve seçime dair basit durumları tutan gözlemlenebilir model.
 Ana Sorumluluklar:
 - Yan menünün görünürlüğünü izlemek ve toggle fonksiyonu sağlamak
 - Ağ/servis katmanından bağımsız hafif bir UI durumu sunmak
 Nerede Kullanılır: MainContentView ve SidebarView.
*/

import SwiftUI
import Combine

@MainActor
class SidebarState: ObservableObject {
    @Published var isVisible: Bool = true
    
    func toggle() {
        isVisible.toggle()
    }
}