/*
 File Overview (EN)
 Purpose: Region code utilities for YouTube (supported list, flag emoji mapping, localized region names).
 Key Responsibilities:
 - Provide a curated list of supported ISO 3166-1 alpha-2 region codes
 - Map region codes to flag emojis and localized display names
 Used By: Services that need region pinning and UI that displays selected region.

 Dosya Özeti (TR)
 Amacı: YouTube için bölge kodu yardımcıları (destekli liste, bayrak emojisi eşleme, yerelleştirilmiş adlar).
 Ana Sorumluluklar:
 - Desteklenen ISO 3166-1 alfa-2 bölge kodlarının listesi
 - Bölge kodlarını bayrak emojilerine ve yerel adlara eşlemek
 Nerede Kullanılır: Bölge sabitlemesi kullanan servisler ve seçili bölgeyi gösteren UI.
*/

import Foundation

struct YouTubeRegions {
    // Broad list of countries where YouTube operates (ISO 3166-1 alpha-2)
    // Not exhaustive, but covers major regions; can be expanded later.
    static let supported: [String] = [
        "GLOBAL",
        // Americas
        "US","CA","MX","BR","AR","CL","CO","PE","VE","UY","PY","BO","EC","GT","CR","PA","DO","PR",
        // Europe
        "GB","IE","FR","DE","IT","ES","PT","NL","BE","LU","CH","AT","SE","NO","DK","FI","IS",
        "PL","CZ","SK","HU","RO","BG","GR","HR","SI","RS","BA","MK","AL","LT","LV","EE","UA",
        // Middle East & Africa
        "TR","IL","SA","AE","QA","KW","BH","OM","EG","MA","TN","DZ","ZA","NG","KE","GH","TZ","UG",
        // Asia Pacific
        "JP","KR","CN","TW","HK","SG","MY","ID","PH","TH","VN","IN","PK","BD","LK","AU","NZ"
    ]

    static func flag(for code: String) -> String {
        guard code.count == 2 else { return "🌐" } // GLOBAL or invalid -> globe
        let base: UInt32 = 127397
        var scalarView = String.UnicodeScalarView()
        for u in code.uppercased().unicodeScalars {
            if let scalar = UnicodeScalar(base + u.value) { scalarView.append(scalar) }
        }
        return String(scalarView)
    }

    static func localizedName(for code: String, appLanguage: AppLanguage) -> String {
        if code == "GLOBAL" { return appLanguage == .tr ? "Global" : "Global" }
        let localeId: String = (appLanguage == .tr) ? "tr_TR" : "en_US"
        let loc = Locale(identifier: localeId)
        return loc.localizedString(forRegionCode: code) ?? code
    }
}
