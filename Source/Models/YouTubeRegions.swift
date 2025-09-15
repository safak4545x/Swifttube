/*
 Overview / Genel Bakış
 EN: Utilities for region codes: supported list, flag emoji mapping, and localized region names.
 TR: Bölge kodları için yardımcılar: destekli liste, bayrak emojisi eşleme ve yerelleştirilmiş adlar.
*/

// EN: Foundation for Locale and Unicode operations. TR: Locale ve Unicode işlemleri için Foundation.
import Foundation

// EN: Namespaced container for region helpers. TR: Bölge yardımcıları için isim alanı.
struct YouTubeRegions {
    // EN: Broad list of supported regions (ISO 3166-1 alpha-2) including a GLOBAL sentinel.
    // TR: GLOBAL dahil desteklenen bölgelerin geniş listesi (ISO 3166-1 alfa-2).
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

    // EN: Convert 2-letter country code to flag emoji; fallback 🌐 for GLOBAL/invalid.
    // TR: 2 harfli ülke kodunu bayrak emojisine çevir; GLOBAL/geçersiz için 🌐 döner.
    static func flag(for code: String) -> String {
        guard code.count == 2 else { return "🌐" } // GLOBAL or invalid -> globe
        let base: UInt32 = 127397
        var scalarView = String.UnicodeScalarView()
        for u in code.uppercased().unicodeScalars {
            if let scalar = UnicodeScalar(base + u.value) { scalarView.append(scalar) }
        }
        return String(scalarView)
    }

    // EN: Localized display name for region based on appLanguage. TR: appLanguage'a göre bölgenin yerelleştirilmiş adı.
    static func localizedName(for code: String, appLanguage: AppLanguage) -> String {
        if code == "GLOBAL" { return appLanguage == .tr ? "Global" : "Global" }
        let localeId: String = (appLanguage == .tr) ? "tr_TR" : "en_US"
        let loc = Locale(identifier: localeId)
        return loc.localizedString(forRegionCode: code) ?? code
    }
}
