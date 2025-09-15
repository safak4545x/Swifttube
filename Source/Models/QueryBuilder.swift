/*
 File Overview (EN)
 Purpose: Central place to compose search queries for different scenarios (home seeds, custom categories).
 Key Responsibilities:
 - Build diversified query lists given language/region and seeds
 - Keep query logic consistent across features
 Used By: YouTubeAPIService search flows.

 Dosya Özeti (TR)
 Amacı: Farklı senaryolar için arama sorgularını (ana tohumlar, özel kategoriler) derleyen merkezi yer.
 Ana Sorumluluklar:
 - Dil/bölge ve tohumlara göre çeşitlendirilmiş sorgu listeleri üretmek
 - Sorgu mantığını özellikler arasında tutarlı kılmak
 Nerede Kullanılır: YouTubeAPIService arama akışları.
*/

import Foundation

/// Sorgu üretimi için tek nokta.
enum QueryBuilder {
    /// hl+gl’den yerel dilde bölge adını üretir (ör. tr+TR -> "Türkiye"). gl boşsa nil.
    static func regionDisplayName(hl: String, gl: String?) -> String? {
        guard let gl = gl, !gl.isEmpty else { return nil }
        let localeId = hl.isEmpty ? "en_US" : "\(hl)_\(gl)"
        let locale = Locale(identifier: localeId)
        return locale.localizedString(forRegionCode: gl) ?? gl
    }

    /// Shorts için tohum sorgular (dil + bölge + isteğe bağlı özel kategori ile).
    /// Davranış, mevcut `localizedShortsQueries()` ile birebir örtüşecek şekilde tasarlanmıştır.
    static func buildShortsSeedQueries(hl: String, gl: String?, selectedCustom: CustomCategory?) -> [String] {
        let regionName = regionDisplayName(hl: hl, gl: gl)
        let markers = LanguageResources.shortsMarkers(for: hl)
        // Hafif trend tohumları (dil bazlı)
        let trendingTerms: [String: [String]] = [
            "en": ["trending", "viral", "popular"],
            "tr": ["trend", "viral", "popüler"],
            "es": ["tendencias", "viral", "populares"],
            "de": ["trends", "viral", "beliebt"],
            "fr": ["tendances", "viral", "populaire"],
            "it": ["tendenze", "virale", "popolari"],
            "pt": ["em alta", "viral", "populares"],
            "ru": ["в тренде", "виральные", "популярные"],
            "ja": ["急上昇", "バズ", "人気"],
            "ko": ["급상승", "바이럴", "인기"],
            "zh": ["趋势", "热门", "流行"],
            "nl": ["trending", "viral", "populair"],
            "pl": ["na czasie", "viral", "popularne"],
            "sv": ["trendar", "viral", "populära"],
            "no": ["trender", "viral", "populære"],
            "da": ["trender", "viral", "populære"],
            "fi": ["trendaavat", "viraali", "suositut"],
            "cs": ["trendy", "virální", "populární"],
            "sk": ["trendy", "virálne", "populárne"]
        ]
        let trendingSeeds = trendingTerms[hl] ?? trendingTerms["en"]!

        var queries: [String] = []

        // Özel kategori seçiliyse: anahtar kelimeler + markers (+ bölge adı) ile güçlü bias
        if let custom = selectedCustom {
            var keyParts: [String] = []
            let p = custom.primaryKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
            if !p.isEmpty { keyParts.append(p) }
            for opt in [custom.secondaryKeyword, custom.thirdKeyword, custom.fourthKeyword] {
                if let s = opt, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { keyParts.append(s) }
            }
            let base = keyParts.joined(separator: " ")
            if !base.isEmpty {
                for m in markers.prefix(4) {
                    if let r = regionName { queries.append("\(base) \(m) \(r)") }
                    queries.append("\(base) \(m)")
                }
                if let r = regionName { queries.append("\(base) \(r) #shorts") }
                queries.append("\(base) #shorts")
            }
        }

        // Saf marker’lar (+ bölge)
        if let r = regionName { queries += markers.map { "\($0) \(r)" } }
        queries += markers

        // Özel kategori yoksa: trend + marker (+ bölge) kombinasyonları
        if selectedCustom == nil {
            for t in trendingSeeds.prefix(3) {
                for m in markers.prefix(3) {
                    if let r = regionName { queries.append("\(t) \(m) \(r)") }
                    queries.append("\(t) \(m)")
                }
            }
        }

        // Dedup ve limit
        var seen = Set<String>()
        let dedup = queries.filter { seen.insert($0.lowercased()).inserted }
        return Array(dedup.prefix(20))
    }

    /// Home (recommendations) için tohum sorgular: son izleme geçmişinden çıkan kanal ve anahtar kelimelerden,
    /// isteğe bağlı bölge adı ile zenginleştirilmiş ve davranış birebir korunmuş biçimde üretir.
    /// - Parameters:
    ///   - hl: Dil kodu (ör. "tr", "en")
    ///   - gl: Bölge kodu (ör. "TR", "US") veya nil
    ///   - topChannels: İzleme geçmişinden türetilen en sık kanallar
    ///   - topWords: İzleme geçmişinden türetilen en sık anahtar kelimeler
    /// - Returns: Çeşitli tohum sorgular (dedupe uygulanmış)
    static func buildHomeSeedQueries(hl: String, gl: String?, topChannels: [String], topWords: [String]) -> [String] {
        var queries: [String] = []
        // Kanal bazlı: "<kanal> new videos"
        for ch in topChannels { queries.append("\(ch) new videos") }
        // Kelime bazlı: kelimenin kendisi
        for w in topWords { queries.append(w) }
        // Bölge adı ile kombine (ilk 3 kelime)
        if let regionName = regionDisplayName(hl: hl, gl: gl) {
            queries += topWords.prefix(3).map { "\($0) \(regionName)" }
        }
        // Tamamen boş ise varsayılanlar
        if queries.isEmpty { queries = ["popular videos", "recommended videos"] }
        // Dedupe (sıra korunarak)
        var seen = Set<String>()
        let dedup = queries.filter { seen.insert($0.lowercased()).inserted }
        return dedup
    }

    /// Özel kategori için aday arama sorguları üretir (mevcut davranışla aynı):
    /// - base query (primary + optional extras)
    /// - primary + each extra
    /// - region-name variant (primary + region display name)
    /// - generic boosters ("primary video")
    static func buildCustomCategoryQueries(hl: String, gl: String?, custom: CustomCategory) -> [String] {
        var candidates: [String] = []
        let primary = custom.primaryKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        let extras = [custom.secondaryKeyword, custom.thirdKeyword, custom.fourthKeyword]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Base query: primary + extras
        var parts: [String] = []
        if !primary.isEmpty { parts.append(primary) }
        parts.append(contentsOf: extras)
        if !parts.isEmpty { candidates.append(parts.joined(separator: " ")) }

        // primary + each extra
        for e in extras { candidates.append("\(primary) \(e)") }

        // Region display name variant
        if let r = regionDisplayName(hl: hl, gl: gl) {
            candidates.append("\(primary) \(r)")
        }

        // Generic boosters
        if !primary.isEmpty { candidates.append("\(primary) video") }

        // Dedupe preserving order
        var seen = Set<String>()
        return candidates.filter { seen.insert($0.lowercased()).inserted }
    }
}
