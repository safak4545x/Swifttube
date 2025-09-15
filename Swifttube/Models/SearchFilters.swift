/*
 Overview / Genel Bakış
 EN: Search filters for date and duration, providing display strings for the UI.
 TR: UI için gösterim metinleri sunan tarih ve süre arama filtreleri.
*/

import Foundation

// EN: Date filters. TR: Tarih filtreleri.
enum SearchDateFilter: String, CaseIterable, Identifiable {
    case lastHour
    case today
    case thisWeek
    case thisMonth
    case thisYear
    case none
    
    // EN: Stable identifier. TR: Stabil kimlik.
    var id: String { rawValue }
    
    // EN: Display string for the UI. TR: UI'da gösterilecek metin.
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

// EN: Duration filters. TR: Süre filtreleri.
enum SearchDurationFilter: String, CaseIterable, Identifiable {
    case under4
    case fourToTen
    case tenToThirty
    case thirtyToSixty
    case overSixty
    case none
    
    // EN: Stable identifier. TR: Stabil kimlik.
    var id: String { rawValue }
    
    // EN: Display string for the UI. TR: UI'da gösterilecek metin.
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
