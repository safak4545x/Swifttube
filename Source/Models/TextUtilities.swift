/*
 Overview / Genel Bakış
 EN: Central text helpers for HTML sanitization and linkifying timestamps/URLs.
 TR: HTML temizleme ve zaman damgalarını/URL'leri linke dönüştürme için merkezi metin yardımcıları.
*/

import Foundation
import SwiftUI

// Shared text helpers for description/comment rendering.
// Centralize HTML entity decode and timestamp linkification used across multiple views.
struct TextUtilities {
    // EN: Decode/sanitize HTML and produce clean plain text. TR: HTML'i çözüp temizleyerek sade metin üret.
    static func sanitizedHTML(_ raw: String?) -> String {
        guard var text = raw, !text.isEmpty else { return "" }
        // EN: Decode HTML entities (e.g., &amp; -> &). TR: HTML entity'leri çöz (örn. &amp; -> &).
        text = ParsingUtils.decodeHTMLEntities(text)
        // EN: Strip script/style blocks; normalize whitespace. TR: script/style bloklarını çıkar; boşlukları normalize et.
        text = text.replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?<\\/script>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?<\\/style>", with: "", options: .regularExpression)
        // EN: Map <br> and </p> to newlines for readability. TR: <br> ve </p> etiketlerini yeni satıra çevir.
        text = text.replacingOccurrences(of: "<br[ \\t]*\\/?>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<\\/p>", with: "\n\n", options: .regularExpression)
        // EN: Strip remaining tags, keep inner text. TR: Kalan etiketleri temizle, iç metni koru.
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // EN: If single-line text has many timestamps, insert newlines before later ones. TR: Tek satırda çok timestamp varsa, sonrakilerden önce satır başı ekle.
        if !text.contains("\n") {
            let pattern = "((?:[0-9]{1,2}:)?[0-5]?[0-9]:[0-5][0-9])"
            if let re = try? NSRegularExpression(pattern: pattern) {
                let ns = text as NSString
                let matches = re.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
                if matches.count >= 3 {
                    var out = String()
                    var last = 0
                    for (i, m) in matches.enumerated() {
                        let start = m.range.location
                        // EN: Segment before the match. TR: Eşleşme öncesi bölüm.
                        if i == 0 {
                            out += ns.substring(with: NSRange(location: last, length: start - last))
                        } else {
                            // EN: Trim trailing spaces of previous segment and insert newline. TR: Önceki bölümün sondaki boşluklarını kırp ve satır ekle.
                            var seg = ns.substring(with: NSRange(location: last, length: start - last))
                            while seg.last?.isWhitespace == true { seg.removeLast() }
                            out += seg + "\n"
                        }
                        // EN: Append matched timestamp token. TR: Eşleşen timestamp'i ekle.
                        out += ns.substring(with: m.range)
                        last = start + m.range.length
                    }
                    // EN: Append remaining tail. TR: Kalan kuyruğu ekle.
                    if last < ns.length {
                        out += ns.substring(with: NSRange(location: last, length: ns.length - last))
                    }
                    text = out
                }
            }
        }
        // EN: Collapse 3+ newlines to 2. TR: 3+ yeni satırı 2'ye indir.
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// EN: Find timestamps like 0:15 or 1:02:03 and return ranges. TR: 0:15 veya 1:02:03 gibi timestamp aralıklarını bul.
    static func timestampMatches(in text: String) -> [NSTextCheckingResult] {
        // EN: Match H:MM:SS or MM:SS; avoid 1.2.3-like patterns. TR: H:MM:SS veya MM:SS; 1.2.3 benzeri kalıpları alma.
        let pattern = "(?:(?<!\\d)([0-9]{1,2}):)?([0-5]?[0-9]):([0-5][0-9])"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex?.matches(in: text, options: [], range: range) ?? []
    }

    /// EN: Convert H:MM:SS or MM:SS timestamp to seconds. TR: H:MM:SS veya MM:SS timestamp'ini saniyeye çevir.
    static func seconds(from timestamp: String) -> Int? {
        let parts = timestamp.split(separator: ":").map { Int($0) ?? 0 }
        guard parts.count == 2 || parts.count == 3 else { return nil }
        if parts.count == 2 { return parts[0] * 60 + parts[1] }
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    }

    /// EN: Create AttributedString with clickable URLs; convert timestamps into yT seek links. TR: Tıklanabilir URL'ler ve timestamp'leri yT arama (seek) bağlantılarına dönüştür.
    static func linkifiedAttributedString(from raw: String) -> AttributedString {
        let clean = sanitizedHTML(raw)
        let ns = clean as NSString
        // EN: Token kind is either "url" or "timestamp". TR: Token türü "url" veya "timestamp".
        var tokens: [(range: NSRange, kind: String)] = [] // "url" | "timestamp"

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let matches = detector.matches(in: clean, options: [], range: NSRange(location: 0, length: ns.length))
            for m in matches where m.url != nil { tokens.append((m.range, "url")) }
        }
        let tsPattern = "(?:(?:([0-9]{1,2}):)?([0-5]?[0-9])):([0-5][0-9])"
        if let tsRegex = try? NSRegularExpression(pattern: tsPattern) {
            let tsMatches = tsRegex.matches(in: clean, range: NSRange(location: 0, length: ns.length))
            for m in tsMatches { tokens.append((m.range, "timestamp")) }
        }
        if tokens.isEmpty { return AttributedString(clean) }
        // EN: Sort by location and drop overlapping tokens. TR: Konuma göre sırala, çakışan token'ları at.
        tokens.sort { $0.range.location < $1.range.location }
        var filtered: [(NSRange, String)] = []
        for t in tokens {
            if let last = filtered.last, NSIntersectionRange(last.0, t.range).length > 0 { continue }
            filtered.append(t)
        }
        var result = AttributedString()
        var cursor = 0
        for (range, kind) in filtered {
            if range.location > cursor {
                let slice = ns.substring(with: NSRange(location: cursor, length: range.location - cursor))
                result.append(AttributedString(slice))
            }
            let tokenText = ns.substring(with: range)
            var attr = AttributedString(tokenText)
            switch kind {
            case "url":
                if let url = URL(string: tokenText) { attr.link = url }
                attr.foregroundColor = .blue
            case "timestamp":
                if let tsRegex = try? NSRegularExpression(pattern: tsPattern),
                   let m = tsRegex.firstMatch(in: tokenText, range: NSRange(location: 0, length: (tokenText as NSString).length)) {
                    var hours = 0
                    if m.range(at: 1).location != NSNotFound { hours = Int((tokenText as NSString).substring(with: m.range(at: 1))) ?? 0 }
                    let minutes = Int((tokenText as NSString).substring(with: m.range(at: 2))) ?? 0
                    let seconds = Int((tokenText as NSString).substring(with: m.range(at: 3))) ?? 0
                    let total = hours * 3600 + minutes * 60 + seconds
                    attr.link = URL(string: "ytseek://\(total)")
                }
                attr.foregroundColor = .blue
            default: break
            }
            result.append(attr)
            cursor = range.location + range.length
        }
        if cursor < ns.length {
            let tail = ns.substring(with: NSRange(location: cursor, length: ns.length - cursor))
            result.append(AttributedString(tail))
        }
        return result
    }
}
