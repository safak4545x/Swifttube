/*
 File Overview (EN)
 Purpose: Centralized text helpers for HTML sanitization, timestamp detection, linkification, counts/dates normalization.
 Key Responsibilities:
 - Decode/sanitize HTML and convert rich text into AttributedString with links
 - Parse/format view counts and dates into consistent localized display
 - Provide reusable helpers for durations and thumbnails
 Used By: VideoDetailView, RelatedVideosView, comments UI, and various labels across the app.

 Dosya Özeti (TR)
 Amacı: HTML temizleme, zaman damgası tespiti, linkleştirme, sayı/tarih normalizasyonu için merkezi metin yardımcıları.
 Ana Sorumluluklar:
 - HTML'i çözümleyip temizlemek ve bağlantılı AttributedString üretmek
 - Görüntülenme sayısı ve tarihleri tutarlı yerelleştirilmiş biçimde üretmek
 - Süre ve küçük resim gibi tekrar kullanılabilir yardımcılar sağlamak
 Nerede Kullanılır: VideoDetailView, RelatedVideosView, yorum arayüzü ve uygulamadaki çeşitli etiketler.
*/

import Foundation
import SwiftUI

// Shared text helpers for description/comment rendering.
// Centralize HTML entity decode and timestamp linkification used across multiple views.
struct TextUtilities {
    static func sanitizedHTML(_ raw: String?) -> String {
        guard var text = raw, !text.isEmpty else { return "" }
        // Decode HTML entities first using existing utility.
        text = ParsingUtils.decodeHTMLEntities(text)
        // Basic sanitization: remove script/style tags and normalize whitespace.
        text = text.replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?<\\/script>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?<\\/style>", with: "", options: .regularExpression)
        // Replace <br> and <p> with newlines for readable SwiftUI Text.
        text = text.replacingOccurrences(of: "<br[ \\t]*\\/?>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<\\/p>", with: "\n\n", options: .regularExpression)
        // Strip remaining HTML tags but keep inner text.
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // If the whole text is a single line but contains multiple timestamps, break lines before later timestamps for readability.
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
                        // Segment before the match
                        if i == 0 {
                            out += ns.substring(with: NSRange(location: last, length: start - last))
                        } else {
                            // Trim trailing whitespace from previous segment and inject a newline before this timestamp
                            var seg = ns.substring(with: NSRange(location: last, length: start - last))
                            while seg.last?.isWhitespace == true { seg.removeLast() }
                            out += seg + "\n"
                        }
                        // Append the matched timestamp token
                        out += ns.substring(with: m.range)
                        last = start + m.range.length
                    }
                    // Append the tail
                    if last < ns.length {
                        out += ns.substring(with: NSRange(location: last, length: ns.length - last))
                    }
                    text = out
                }
            }
        }
        // Collapse excessive blank lines.
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Finds timestamps like 0:15, 1:02:03 and returns ranges for linking.
    static func timestampMatches(in text: String) -> [NSTextCheckingResult] {
        // Matches H:MM:SS or MM:SS; avoid picking up version numbers like 1.2.3
        let pattern = "(?:(?<!\\d)([0-9]{1,2}):)?([0-5]?[0-9]):([0-5][0-9])"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex?.matches(in: text, options: [], range: range) ?? []
    }

    /// Converts a timestamp string H:MM:SS or MM:SS to seconds.
    static func seconds(from timestamp: String) -> Int? {
        let parts = timestamp.split(separator: ":").map { Int($0) ?? 0 }
        guard parts.count == 2 || parts.count == 3 else { return nil }
        if parts.count == 2 { return parts[0] * 60 + parts[1] }
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    }

    /// Returns an AttributedString where URLs are linked and timestamps are converted to `ytseek://<seconds>` links.
    static func linkifiedAttributedString(from raw: String) -> AttributedString {
        let clean = sanitizedHTML(raw)
        let ns = clean as NSString
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
