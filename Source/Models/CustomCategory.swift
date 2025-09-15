/*
 Overview / Genel Bakış
 EN: User-defined custom categories with keywords, optional color, and date filter for Home feed.
 TR: Ana sayfa akışı için anahtar kelimeler, isteğe bağlı renk ve tarih filtresi içeren kullanıcı tanımlı kategoriler.
*/

import Foundation
import SwiftUI

// MARK: - User-defined Category Model / Kullanıcı Tanımlı Kategori Modeli
struct CustomCategory: Identifiable, Codable, Equatable {
    // EN: Unique id for identification/persistence. TR: Tanımlama/kalıcılık için benzersiz id.
    let id: UUID
    // EN: Display name (shown on Category Bar). TR: Görünen ad (Kategori Çubuğunda gösterilir).
    var name: String
    // EN: Primary keyword (must be a single word). TR: Birincil anahtar kelime (tek kelime olmalı).
    var primaryKeyword: String
    // EN: Optional secondary keyword. TR: İsteğe bağlı ikincil anahtar kelime.
    var secondaryKeyword: String?
    // EN: Optional 3rd keyword. TR: İsteğe bağlı 3. anahtar kelime.
    var thirdKeyword: String?
    // EN: Optional 4th keyword. TR: İsteğe bağlı 4. anahtar kelime.
    var fourthKeyword: String?
    // EN: Upload time filter to narrow results. TR: Son yüklenme zamanına göre filtre.
    var dateFilter: CustomDateFilter
    /// Optional named color for active highlight. Default (nil) uses app accent color.
    // TR: Etkin vurgulama için isteğe bağlı adlandırılmış renk. Varsayılan (nil) uygulama vurgu rengini kullanır.
    var colorName: String?

    // EN: Designated initializer for category fields. TR: Kategori alanları için atanan kurucu.
    init(id: UUID = UUID(), name: String, primaryKeyword: String, secondaryKeyword: String? = nil, thirdKeyword: String? = nil, fourthKeyword: String? = nil, dateFilter: CustomDateFilter = .none, colorName: String? = nil) {
        self.id = id
        self.name = name
        self.primaryKeyword = primaryKeyword
        self.secondaryKeyword = secondaryKeyword
        self.thirdKeyword = thirdKeyword
        self.fourthKeyword = fourthKeyword
        self.dateFilter = dateFilter
        self.colorName = colorName
    }
}

// MARK: - Date filter (upload time) / Tarih filtresi (yükleme zamanı)
enum CustomDateFilter: String, CaseIterable, Identifiable, Codable {
    // EN: No filter. TR: Filtre yok.
    case none
    // EN: Last 7 days. TR: Son 1 hafta.
    case lastWeek
    // EN: Last 1 month. TR: Son 1 ay.
    case lastMonth
    // EN: Last 1 year. TR: Son 1 yıl.
    case lastYear
    // EN: Shuffle without a time cutoff. TR: Zaman sınırsız karıştırma.
    case random

    // EN: Stable id from rawValue. TR: rawValue'dan türetilen stabil id.
    var id: String { rawValue }

    // EN: Localization key for UI. TR: UI için yerelleştirme anahtarı.
    var localizationKey: Localizer.Key {
        switch self {
        case .none: return .customDateNone
        case .lastWeek: return .customDateLastWeek
        case .lastMonth: return .customDateLastMonth
        case .lastYear: return .customDateLastYear
        case .random: return .customDateRandom
        }
    }

    /// Returns a cutoff Date if filter is active, otherwise nil
    // TR: Filtre etkinse bir eşik tarihi döndürür, değilse nil.
    var cutoffDate: Date? {
        let now = Date()
    switch self {
    case .none: return nil
    case .lastWeek: return Calendar.current.date(byAdding: .day, value: -7, to: now)
    case .lastMonth: return Calendar.current.date(byAdding: .month, value: -1, to: now)
    case .lastYear: return Calendar.current.date(byAdding: .year, value: -1, to: now)
    case .random: return nil // same as no cutoff; randomness already applied by shuffle
    }
    }
}

// MARK: - Color helper / Renk yardımcısı
extension Color {
    // EN: Map optional color name to SwiftUI Color. TR: İsteğe bağlı renk adını SwiftUI Color'a eşle.
    static func fromNamed(_ name: String?) -> Color? {
        guard let name = name else { return nil }
        switch name.lowercased() {
        case "blue": return .blue
        case "green": return .green
        case "red": return .red
        case "orange": return .orange
        case "purple": return .purple
        case "pink": return .pink
        case "teal": return .teal
        case "yellow": return .yellow
        case "brown": return .brown
        default: return nil
        }
    }
}
