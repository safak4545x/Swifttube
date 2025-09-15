/*
 Overview / Genel Bakış
 EN: Observable sidebar UI state: only visibility and a toggle helper.
 TR: Gözlemlenebilir yan menü durumu: yalnız görünürlük ve bir toggle yardımcı fonksiyonu.
*/

import SwiftUI
import Combine

@MainActor
class SidebarState: ObservableObject {
    // EN: Whether the sidebar is visible. TR: Yan menünün görünür olup olmadığı.
    @Published var isVisible: Bool = true
    
    // EN: Toggle sidebar visibility. TR: Yan menü görünürlüğünü değiştir.
    func toggle() {
        isVisible.toggle()
    }
}