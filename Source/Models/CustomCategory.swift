/*
 File Overview (EN)
 Purpose: Defines user-configurable custom categories, filters, and persistence identifiers.
 Key Responsibilities:
 - Represent category fields (keywords, date filter)
 - Provide identity for selection and persistence
 Used By: YouTubeAPIService and CategoryBarView.

 Dosya Özeti (TR)
 Amacı: Kullanıcı tarafından yapılandırılabilir özel kategorileri, filtreleri ve kalıcılık kimliklerini tanımlar.
 Ana Sorumluluklar:
 - Kategori alanlarını temsil eder (anahtar kelimeler, tarih filtresi)
 - Seçim ve kalıcılık için kimlik sağlar
 Nerede Kullanılır: YouTubeAPIService ve CategoryBarView.
*/

import Foundation
import SwiftUI

// MARK: - User-defined Category Model
struct CustomCategory: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var primaryKeyword: String
    var secondaryKeyword: String?
    var thirdKeyword: String?
    var fourthKeyword: String?
    var dateFilter: CustomDateFilter
    /// Optional named color for active highlight. Default (nil) uses app accent color.
    var colorName: String?

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

// MARK: - Date filter (upload time)
enum CustomDateFilter: String, CaseIterable, Identifiable, Codable {
    case none
    case lastWeek
    case lastMonth
    case lastYear
    case random

    var id: String { rawValue }

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

// MARK: - Color helper
extension Color {
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
