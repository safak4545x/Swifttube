/*
 File Overview (EN)
 Purpose: Enums and helpers for search date/duration filters used in UI and query composition.
 Key Responsibilities:
 - Represent selectable filters and provide display strings
 - Offer cutoff dates for filtering results
 Used By: HomePageView and YouTubeAPIService.

 Dosya Özeti (TR)
 Amacı: UI ve sorgu derlemede kullanılan arama tarih/süre filtreleri için enum ve yardımcılar.
 Ana Sorumluluklar:
 - Seçilebilir filtreleri ve gösterim metinlerini temsil etmek
 - Sonuçları süzmek için kesim tarihlerini sunmak
 Nerede Kullanılır: HomePageView ve YouTubeAPIService.
*/

import Foundation

// Tarih filtreleri
enum SearchDateFilter: String, CaseIterable, Identifiable {
    case lastHour
    case today
    case thisWeek
    case thisMonth
    case thisYear
    case none
    
    var id: String { rawValue }
    
    var display: String {
        switch self {
        case .lastHour: return "Son 1 Saat"
        case .today: return "Bugün"
        case .thisWeek: return "Bu Hafta"
        case .thisMonth: return "Bu Ay"
        case .thisYear: return "Bu Yıl"
        case .none: return "(Yok)"
        }
    }
}

// Süre filtreleri
enum SearchDurationFilter: String, CaseIterable, Identifiable {
    case under4
    case fourToTen
    case tenToThirty
    case thirtyToSixty
    case overSixty
    case none
    
    var id: String { rawValue }
    
    var display: String {
        switch self {
        case .under4: return "<4 dk"
        case .fourToTen: return "4-10 dk"
        case .tenToThirty: return "10-30 dk"
        case .thirtyToSixty: return "30-60 dk"
        case .overSixty: return ">60 dk"
        case .none: return "(Yok)"
        }
    }
}
