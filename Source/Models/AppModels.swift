
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

import Foundation
import SwiftUI

// Player appearance settings (stored via AppStorage / UserDefaults)
@MainActor
final class PlayerAppearanceSettings: ObservableObject {
    @AppStorage("hideChannelAvatar") var hideChannelAvatar: Bool = false { didSet { broadcast() } }
    @AppStorage("hideChannelName") var hideChannelName: Bool = false { didSet { broadcast() } }
    @AppStorage("hideVideoTitle") var hideVideoTitle: Bool = false { didSet { broadcast() } }
    @AppStorage("hideMoreVideosOverlay") var hideMoreVideosOverlay: Bool = false { didSet { broadcast() } }
    @AppStorage("hideContextMenu") var hideContextMenu: Bool = false { didSet { broadcast() } }
    @AppStorage("hideWatchLater") var hideWatchLater: Bool = false { didSet { broadcast() } }
    @AppStorage("hideShare") var hideShare: Bool = false { didSet { broadcast() } }
    @AppStorage("hideSubtitlesButton") var hideSubtitlesButton: Bool = false { didSet { broadcast() } }
    @AppStorage("hideQualityButton") var hideQualityButton: Bool = false { didSet { broadcast() } }
    @AppStorage("hideYouTubeLogo") var hideYouTubeLogo: Bool = false { didSet { broadcast() } }
    @AppStorage("hideAirPlayButton") var hideAirPlayButton: Bool = false { didSet { broadcast() } }
    @AppStorage("hideChapterTitle") var hideChapterTitle: Bool = false { didSet { broadcast() } }
    @AppStorage("hideScrubPreview") var hideScrubPreview: Bool = false { didSet { broadcast() } }
    // Fullscreen ve PIP butonları artık her zaman gizli; ayar kaldırıldı.

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
    private func broadcast() { NotificationCenter.default.post(name: .playerAppearanceChanged, object: nil) }
}

struct Category: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let url: String
}

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

// App-wide language selection
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
