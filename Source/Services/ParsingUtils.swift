/*
 File Overview (EN)
 Purpose: Shared HTML/JSON parsing helpers used by local adapters to extract YouTube data without official APIs.
 Key Responsibilities:
 - Parse durations, view counts, dates, and localized strings from raw text/HTML
 - Provide safe lookups, regex utilities, and fallback extraction strategies
 - Normalize fields into internal models used by services and views
 Used By: LocalSearchAdapter, LocalRelatedAdapter, LocalYouTubeService, VideoSearchService, etc.

 Dosya Özeti (TR)
 Amacı: Resmi API olmadan YouTube verilerini çıkarmak için yerel adaptörler tarafından kullanılan ortak HTML/JSON ayrıştırma yardımcıları.
 Ana Sorumluluklar:
 - Süre, görüntülenme, tarih ve yerelleştirilmiş metinleri ham metin/HTML'den ayrıştırmak
 - Güvenli erişimler, regex yardımcıları ve yedek çıkarım stratejileri sağlamak
 - Alanları servislerin ve görünümlerin kullandığı iç modellere normalize etmek
 Nerede Kullanılır: LocalSearchAdapter, LocalRelatedAdapter, LocalYouTubeService, VideoSearchService vb.
*/


import Foundation

enum ParsingUtils {
    // Basit marker arası JSON parçası çıkarma
    static func extractJSON(from html: String, startMarker: String, endMarker: String) -> String? {
        guard let startRange = html.range(of: startMarker) else { return nil }
        let afterStart = startRange.upperBound
        guard let endRange = html.range(of: endMarker, range: afterStart..<html.endIndex) else { return nil }
        return String(html[afterStart..<endRange.lowerBound])
    }

    // ytcfg.set({...}) veya ytcfg.data_ = {...} gövdesini parse edip döndürür
    static func extractYtConfig(html: String) -> [String: Any]? {
        let markers = [
            "ytcfg.set(",
            "ytcfg.data_ = "
        ]
        for marker in markers {
            var searchRange = html.startIndex..<html.endIndex
            while let r = html.range(of: marker, options: [], range: searchRange) {
                guard let braceStart = html[r.lowerBound...].firstIndex(of: "{") else { break }
                if let (jsonObj, endIndex) = balancedJSONObject(from: html, startIndex: braceStart) {
                    if let data = jsonObj.data(using: .utf8),
                       let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        // Heuristik: API key varsa bu config işimize yarar
                        if root["INNERTUBE_API_KEY"] != nil || root["INNERTUBE_CONTEXT"] != nil {
                            return root
                        }
                    }
                    searchRange = endIndex..<html.endIndex
                } else {
                    break
                }
            }
        }
        // Son çare: basit string arama ile API key'i çıkarmayı dene
        if let range = html.range(of: "\"INNERTUBE_API_KEY\":\"") {
            let start = range.upperBound
            if let end = html[start...].firstIndex(of: "\"") {
                let key = String(html[start..<end])
                return ["INNERTUBE_API_KEY": key]
            }
        }
        return nil
    }

    // Dengeli süslü ile başlayan JSON objesini döndürür (string kaçışlarını dikkate alır)
    static func balancedJSONObject(from text: String, startIndex: String.Index) -> (String, String.Index)? {
        var i = startIndex
        var depth = 0
        var inString = false
        var escape = false
        let end = text.endIndex
        while i < end {
            let c = text[i]
            if inString {
                if escape { escape = false }
                else if c == "\\" { escape = true }
                else if c == "\"" { inString = false }
            } else {
                if c == "\"" { inString = true }
                else if c == "{" { depth += 1 }
                else if c == "}" {
                    depth -= 1
                    if depth == 0 {
                        let obj = String(text[startIndex...i])
                        return (obj, text.index(after: i))
                    }
                }
                else if c == "<" && depth == 0 { return nil }
            }
            i = text.index(after: i)
        }
        return nil
    }

    // ytInitialData sözlüğünü esnek biçimde bulur ve parse eder
    static func extractInitialDataDict(html: String) -> [String: Any]? {
        let triggers = [
            "ytInitialData = {",
            "var ytInitialData = {",
            "window[\"ytInitialData\"] = {",
            "window.ytInitialData = {",
            "ytInitialData\": {"
        ]
        for trig in triggers {
            var searchRange = html.startIndex..<html.endIndex
            while let r = html.range(of: trig, options: [], range: searchRange) {
                guard let braceStart = html[r.lowerBound...].firstIndex(of: "{") else { break }
                if let (jsonObj, endIndex) = balancedJSONObject(from: html, startIndex: braceStart) {
                    if let data = jsonObj.data(using: .utf8),
                       let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        return root
                    }
                    searchRange = endIndex..<html.endIndex
                } else {
                    break
                }
            }
        }
        // Generic fallback
        if let generic = html.range(of: "ytInitialData"),
           let brace = html[generic.upperBound...].firstIndex(of: "{") {
            if let (jsonObj, _) = balancedJSONObject(from: html, startIndex: brace),
               let data = jsonObj.data(using: .utf8),
               let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return root
            }
        }
        return nil
    }

    // Basit URL normalize: query at, // -> https:, http -> https
    static func normalizeURL(_ raw: String) -> String {
        var u = raw
        if let q = u.firstIndex(of: "?") { u = String(u[..<q]) }
        if u.hasPrefix("//") { u = "https:" + u }
        if u.hasPrefix("http://") { u = u.replacingOccurrences(of: "http://", with: "https://") }
        return u
    }

    // Basit HTML entity decode (sık kullanılanlar)
    static func decodeHTMLEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
         .replacingOccurrences(of: "&quot;", with: "\"")
         .replacingOccurrences(of: "&#39;", with: "'")
         .replacingOccurrences(of: "&lt;", with: "<")
         .replacingOccurrences(of: "&gt;", with: ">")
    }
}
