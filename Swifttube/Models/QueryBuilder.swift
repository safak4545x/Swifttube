/*
 Overview / Genel Bakış
 EN: Centralized builders for query strings (Home, Shorts, Custom Category) to keep behavior consistent.
 TR: Davranışı tutarlı tutmak için sorgu dizgileri (Ana Sayfa, Shorts, Özel Kategori) için merkezi üreticiler.
*/

import Foundation

/// Sorgu üretimi için tek nokta.
enum QueryBuilder {
    /// EN: Make localized region display name from hl+gl (e.g., tr+TR -> "Türkiye"); nil if gl empty. TR: hl+gl'den yerel bölge adı üret; gl boşsa nil.
    static func regionDisplayName(hl: String, gl: String?) -> String? {
        guard let gl = gl, !gl.isEmpty else { return nil }
        let localeId = hl.isEmpty ? "en_US" : "\(hl)_\(gl)"
        let locale = Locale(identifier: localeId)
        return locale.localizedString(forRegionCode: gl) ?? gl
    }

    /// EN: Build Shorts seed queries (language + region + optional custom category) mirroring existing behavior. TR: Mevcut davranışla aynı olacak şekilde Shorts tohum sorguları (dil + bölge + opsiyonel özel kategori) üret.
    static func buildShortsSeedQueries(hl: String, gl: String?, selectedCustom: CustomCategory?) -> [String] {
        let regionName = regionDisplayName(hl: hl, gl: gl)
        let markers = LanguageResources.shortsMarkers(for: hl)
        // EN: Lightweight trending seeds by language. TR: Dile göre hafif trend tohumları.
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

        // EN: If a custom category is selected, bias queries with keywords + markers (+ region). TR: Özel kategori seçiliyse anahtar kelimeler + işaretleyiciler (+ bölge) ile sorgulara ağırlık ver.
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

        // EN: Pure markers (+ region). TR: Salt işaretleyiciler (+ bölge).
        if let r = regionName { queries += markers.map { "\($0) \(r)" } }
        queries += markers

        // EN: If no custom category: trend + marker (+ region) combinations. TR: Özel kategori yoksa: trend + işaretleyici (+ bölge) kombinasyonları.
        if selectedCustom == nil {
            for t in trendingSeeds.prefix(3) {
                for m in markers.prefix(3) {
                    if let r = regionName { queries.append("\(t) \(m) \(r)") }
                    queries.append("\(t) \(m)")
                }
            }
        }

        // EN: Dedupe (case-insensitive) and limit length. TR: Küçük/büyük harf duyarsız tekilleştir ve sınırla.
        var seen = Set<String>()
        let dedup = queries.filter { seen.insert($0.lowercased()).inserted }
        return Array(dedup.prefix(20))
    }

    /// EN: Build Home seed queries from frequent channels/words and optional region name. TR: Ana sayfa tohumlarını sık kanal/kelimelerden ve isteğe bağlı bölge adından üret.
    /// - Parameters:
    ///   - hl: UI language code (e.g., "tr", "en"). TR: UI dil kodu.
    ///   - gl: Region code (e.g., "TR", "US") or nil. TR: Bölge kodu veya nil.
    ///   - topChannels: Frequent channels from watch history. TR: İzleme geçmişinden sık kanallar.
    ///   - topWords: Frequent keywords from watch history. TR: İzleme geçmişinden sık anahtar kelimeler.
    /// - Returns: De-duplicated seed queries. TR: Tekilleştirilmiş tohum sorguları.
    static func buildHomeSeedQueries(hl: String, gl: String?, topChannels: [String], topWords: [String]) -> [String] {
        var queries: [String] = []
        // EN: Channel-based seeds. TR: Kanal tabanlı tohumlar.
        for ch in topChannels { queries.append("\(ch) new videos") }
        // EN: Word-based seeds. TR: Kelime tabanlı tohumlar.
        for w in topWords { queries.append(w) }
        // EN: Combine region display name with first 3 words. TR: İlk 3 kelimeyle bölge adını birleştir.
        if let regionName = regionDisplayName(hl: hl, gl: gl) {
            queries += topWords.prefix(3).map { "\($0) \(regionName)" }
        }
        // EN: Fallback seeds if empty. TR: Boşsa varsayılan tohumlar.
        if queries.isEmpty { queries = ["popular videos", "recommended videos"] }
        // EN: Dedupe preserving order. TR: Sıra korunarak tekilleştir.
        var seen = Set<String>()
        let dedup = queries.filter { seen.insert($0.lowercased()).inserted }
        return dedup
    }

    /// EN: Build candidate queries for a custom category (same behavior as existing). TR: Özel kategori için aday sorguları üret (mevcut davranış ile aynı).
    /// - base query (primary + optional extras). TR: temel sorgu (birincil + opsiyoneller)
    /// - primary + each extra. TR: birincil + her bir ek
    /// - region-name variant. TR: bölge adı varyantı
    /// - generic boosters ("primary video"). TR: genel güçlendiriciler ("primary video")
    static func buildCustomCategoryQueries(hl: String, gl: String?, custom: CustomCategory) -> [String] {
        var candidates: [String] = []
        let primary = custom.primaryKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        let extras = [custom.secondaryKeyword, custom.thirdKeyword, custom.fourthKeyword]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // EN: Base query: primary + extras. TR: Temel sorgu: birincil + ekler.
        var parts: [String] = []
        if !primary.isEmpty { parts.append(primary) }
        parts.append(contentsOf: extras)
        if !parts.isEmpty { candidates.append(parts.joined(separator: " ")) }

        // EN: Primary + each extra. TR: Birincil + her bir ek.
        for e in extras { candidates.append("\(primary) \(e)") }

        // EN: Region display name variant. TR: Bölge adı varyantı.
        if let r = regionDisplayName(hl: hl, gl: gl) {
            candidates.append("\(primary) \(r)")
        }

        // EN: Generic boosters. TR: Genel güçlendiriciler.
        if !primary.isEmpty { candidates.append("\(primary) video") }

        // EN: Dedupe preserving order. TR: Sıra korunarak tekilleştir.
        var seen = Set<String>()
        return candidates.filter { seen.insert($0.lowercased()).inserted }
    }
}
