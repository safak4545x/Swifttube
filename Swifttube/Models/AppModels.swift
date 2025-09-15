
/*
 File Overview (EN)
 Purpose: App-specific lightweight models and DTOs not tied to YouTube primitives.
 Key Responsibilities:
 - Define small structs/enums used by UI and services
 - Keep types decoupled from backend-specific models
 Used By: Various UI flows.

 Dosya Özeti (TR)
 Amacı: YouTube ana modellerine bağlı olmayan, uygulamaya özgü hafif modeller ve DTO'lar.
 Ana Sorumluluklar:
 - UI ve servislerde kullanılan küçük struct/enum tiplerini tanımlamak
 - Tipleri backend'e özgü modellerden ayrık tutmak
 Nerede Kullanılır: Çeşitli UI akışları.
*/

// EN: Foundation for base types, SwiftUI for @AppStorage and ObservableObject. TR: Temel tipler için Foundation, @AppStorage ve ObservableObject için SwiftUI.
import Foundation
import SwiftUI

// EN: Player appearance settings persisted in AppStorage (UserDefaults). TR: AppStorage'da (UserDefaults) saklanan oynatıcı görünüm ayarları.
@MainActor
final class PlayerAppearanceSettings: ObservableObject {
    // EN: Top overlay controls/labels. TR: Üst katmandaki kontrol/etiketler.
    @AppStorage("hideChannelAvatar") var hideChannelAvatar: Bool = false { didSet { broadcast() } }
    @AppStorage("hideChannelName") var hideChannelName: Bool = false { didSet { broadcast() } }
    @AppStorage("hideVideoTitle") var hideVideoTitle: Bool = false { didSet { broadcast() } }
    @AppStorage("hideMoreVideosOverlay") var hideMoreVideosOverlay: Bool = false { didSet { broadcast() } }
    @AppStorage("hideContextMenu") var hideContextMenu: Bool = false { didSet { broadcast() } }
    @AppStorage("hideWatchLater") var hideWatchLater: Bool = false { didSet { broadcast() } }
    @AppStorage("hideShare") var hideShare: Bool = false { didSet { broadcast() } }
    // EN: Bottom controls and overlays. TR: Alt kontroller ve katmanlar.
    @AppStorage("hideSubtitlesButton") var hideSubtitlesButton: Bool = false { didSet { broadcast() } }
    @AppStorage("hideQualityButton") var hideQualityButton: Bool = false { didSet { broadcast() } }
    @AppStorage("hideYouTubeLogo") var hideYouTubeLogo: Bool = false { didSet { broadcast() } }
    @AppStorage("hideAirPlayButton") var hideAirPlayButton: Bool = false { didSet { broadcast() } }
    @AppStorage("hideChapterTitle") var hideChapterTitle: Bool = false { didSet { broadcast() } }
    @AppStorage("hideScrubPreview") var hideScrubPreview: Bool = false { didSet { broadcast() } }
    // Fullscreen ve PIP butonları artık her zaman gizli; ayar kaldırıldı.

    // EN: Restore all controls to default (visible). TR: Tüm kontrolleri varsayılana (görünür) döndür.
    func reset() {
        hideChannelAvatar = false
        hideChannelName = false
    hideVideoTitle = false
    hideMoreVideosOverlay = false
    hideContextMenu = false
        hideWatchLater = false
        hideShare = false
        hideSubtitlesButton = false
        hideQualityButton = false
        hideYouTubeLogo = false
        hideAirPlayButton = false
    hideChapterTitle = false
    hideScrubPreview = false
    }
    // EN: Notify active players/webviews to update UI without full reload. TR: Aktif oynatıcıları/webview'leri tam yeniden yüklemeden UI güncellemesi için bilgilendir.
    private func broadcast() { NotificationCenter.default.post(name: .playerAppearanceChanged, object: nil) }
}

// EN: Simple display category with a title and URL. TR: Başlık ve URL içeren basit görüntü kategorisi.
struct Category: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let url: String
}

// EN: Sidebar navigation item with system icon name and target URL. TR: Sistem ikon adı ve hedef URL ile yan menü öğesi.
struct SidebarItem: Identifiable, Hashable {
    let id: String
    let systemName: String
    let title: String
    let url: String

    init(systemName: String, title: String, url: String) {
        self.id = url
        self.systemName = systemName
        self.title = title
        self.url = url
    }
}

// EN: App-wide language selection enum with display names. TR: Görünen adlarla uygulama geneli dil seçimi enum'u.
enum AppLanguage: String, CaseIterable, Identifiable {
    case en
    case tr
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .en: return "English"
        case .tr: return "Türkçe"
        }
    }
}
