/*
 File Overview (EN)
 Purpose: Small reusable utilities and extensions (safe subscripts, clamping, count/date formatting, parsing helpers).
 Key Responsibilities:
 - Provide safe collection access and value clamping
 - Format view counts, short counts, and humanized dates
 - Parse approximate numbers from localized text and normalize avatar/thumbnail URLs
 Used By: Many views and services that render counts/dates and handle arrays safely.

 Dosya Özeti (TR)
 Amacı: Küçük tekrar kullanılabilir yardımcılar ve uzatmalar (güvenli subscript, clamp, sayı/tarih formatlama, ayrıştırma).
 Ana Sorumluluklar:
 - Koleksiyonlara güvenli erişim ve değer sıkıştırma (clamp)
 - Görüntülenme sayısı, kısa sayı ve insansı tarih formatlama
 - Yerelleştirilmiş metinden yaklaşık sayı ayrıştırma ve avatar/thumbnail URL normalizasyonu
 Nerede Kullanılır: Dizileri güvenli kullanma ve sayı/tarih gösterimi yapan pek çok view ve servis.
*/

import Foundation

// Safe index access for arrays
extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// Clamp helper
extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        if self < limits.lowerBound { return limits.lowerBound }
        if self > limits.upperBound { return limits.upperBound }
        return self
    }
}

// Utility Functions
func formatViewCount(_ countString: String) -> String {
    let lang = UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.en.rawValue
    // Preserve any non-numeric placeholder (e.g., Loading…)
    guard let count = Int(countString) else {
        // If it's exactly the legacy Turkish placeholder, localize it
        if countString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("yükleniyor") {
            return lang == AppLanguage.tr.rawValue ? "Yükleniyor..." : "Loading..."
        }
        return countString
    }

    let d = Double(count)
    // Abbreviations K/M/B are language-agnostic; only suffix differs
    let suffix = (lang == AppLanguage.tr.rawValue) ? "görüntülenme" : "views"
    if count >= 1_000_000_000 {
        return String(format: d >= 10_000_000_000 ? "%.0fB %@" : "%.1fB %@", d / 1_000_000_000, suffix)
    } else if count >= 1_000_000 {
        return String(format: d >= 10_000_000 ? "%.0fM %@" : "%.1fM %@", d / 1_000_000, suffix)
    } else if count >= 1_000 {
        return String(format: d >= 10_000 ? "%.0fK %@" : "%.1fK %@", d / 1_000, suffix)
    } else {
        return "\(count) \(suffix)"
    }
}

// Kısaltılmış sayı formatı (sadece sayı, son ek yok) - örn: 987, 1.2K, 3.4M, 1.1B
func formatCountShort(_ countString: String) -> String {
    guard let count = Int(countString) else { return "0" }
    let d = Double(count)
    if count >= 1_000_000_000 {
        return String(format: d >= 10_000_000_000 ? "%.0fB" : "%.1fB", d / 1_000_000_000)
    } else if count >= 1_000_000 {
        return String(format: d >= 10_000_000 ? "%.0fM" : "%.1fM", d / 1_000_000)
    } else if count >= 1_000 {
        return String(format: d >= 10_000 ? "%.0fK" : "%.1fK", d / 1_000)
    } else {
        return String(count)
    }
}

// Parse an approximate number from a localized string such as:
//  "1.2K", "3,4K", "2 Mn", "1.5M", "12 B", or grouped digits like "123.456".
// Returns an integer best-effort approximation (e.g., 1200, 3400, 2_000_000).
func approxNumberFromText(_ text: String) -> Int? {
    let s = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !s.isEmpty else { return nil }

    // 1) Binlik gruplama: 1.234.567 / 1,234,567 / 1 234 567
    if let re = try? NSRegularExpression(pattern: #"(?<!\d)(\d{1,3}(?:[\.,\s]\d{3})+)(?!\d)"#, options: []),
       let m = re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)), m.numberOfRanges > 1 {
        let r = m.range(at: 1)
        if r.location != NSNotFound, let rr = Range(r, in: s) {
            let token = String(s[rr])
            let cleaned = token.replacingOccurrences(of: #"[\s\.,]"#, with: "", options: .regularExpression)
            if let n = Int(cleaned) { return n }
        }
    }

    // 2) Sonekli yaklaşık sayılar: 1.2K, 3,4M, 2 Mn, 1B
    if let re = try? NSRegularExpression(pattern: #"(?i)(?<!\d)(\d+(?:[\.,]\d+)?)\s*(k|m|b|mn)\b"#, options: []),
       let m = re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)), m.numberOfRanges > 2 {
        let ns = s as NSString
        let numStr = ns.substring(with: m.range(at: 1)).replacingOccurrences(of: ",", with: ".")
        let unit = ns.substring(with: m.range(at: 2)).lowercased()
        guard let val = Double(numStr) else { return nil }
        let mult: Double
        switch unit {
        case "k": mult = 1_000
        case "m", "mn": mult = 1_000_000
        case "b": mult = 1_000_000_000
        default: mult = 1
        }
        return Int(val * mult)
    }

    // 3) Düz rakam (örn: 51552)
    if let re = try? NSRegularExpression(pattern: #"(?<!\d)(\d{2,})(?!\d)"#, options: []),
       let m = re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)), m.numberOfRanges > 1 {
        let ns = s as NSString
        if let n = Int(ns.substring(with: m.range(at: 1))) { return n }
    }

    return nil
}

func formatDate(_ dateString: String) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
    formatter.timeZone = TimeZone(abbreviation: "UTC")

    guard let date = formatter.date(from: dateString) else {
        return dateString
    }

    let now = Date()
    let calendar = Calendar.current
    let components = calendar.dateComponents([.year, .month, .weekOfYear, .day, .hour, .minute], from: date, to: now)
    let lang = UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.en.rawValue

    func ago(_ value: Int, singular: String, plural: String) -> String {
        if lang == AppLanguage.tr.rawValue {
            return value == 1 ? "1 \(singular) önce" : "\(value) \(plural) önce"
        } else {
            // English singular/plural already provided
            return value == 1 ? "1 \(singular) ago" : "\(value) \(plural) ago"
        }
    }

    if let years = components.year, years > 0 {
        return lang == AppLanguage.tr.rawValue ? ago(years, singular: "yıl", plural: "yıl") : ago(years, singular: "year", plural: "years")
    }
    if let months = components.month, months > 0 {
        return lang == AppLanguage.tr.rawValue ? ago(months, singular: "ay", plural: "ay") : ago(months, singular: "month", plural: "months")
    }
    if let weeks = components.weekOfYear, weeks > 0 {
        return lang == AppLanguage.tr.rawValue ? ago(weeks, singular: "hafta", plural: "hafta") : ago(weeks, singular: "week", plural: "weeks")
    }
    if let days = components.day, days > 0 {
        return lang == AppLanguage.tr.rawValue ? ago(days, singular: "gün", plural: "gün") : ago(days, singular: "day", plural: "days")
    }
    if let hours = components.hour, hours > 0 {
        return lang == AppLanguage.tr.rawValue ? ago(hours, singular: "saat", plural: "saat") : ago(hours, singular: "hour", plural: "hours")
    }
    if let minutes = components.minute, minutes > 0 {
        return lang == AppLanguage.tr.rawValue ? ago(minutes, singular: "dakika", plural: "dakika") : ago(minutes, singular: "minute", plural: "minutes")
    }
    return lang == AppLanguage.tr.rawValue ? "Az önce" : "Just now"
}

// MARK: - Relative date parsing (language-agnostic input -> ISO8601)
/// Convert a localized relative time string (e.g., "5 days ago", "3 yıl önce", "vor 2 Jahren",
/// "hace 2 años", "il y a 3 mois", "2 недели назад") to an ISO8601 date string.
/// The output is purely date math and does not depend on device region; use formatDate(_) to display.
func relativeStringToISO(_ raw: String) -> String? {
    let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !lower.isEmpty else { return nil }
    // Extract first integer from the string (supports all Unicode digits)
    let digits = String(lower.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) })
    guard let n = Int(digits), n > 0 else { return nil }

    // Tokenize into words using unicode letters; ensures we match whole words
    // This prevents collisions like TR "ay" (month) matching EN "days".
    let wordSeparator = CharacterSet.letters.inverted
    let words = lower.components(separatedBy: wordSeparator).filter { !$0.isEmpty }
    let wordSet = Set(words)
    // Helper to test if any of the tokens appear as whole words
    func has(_ tokens: [String]) -> Bool { tokens.contains { wordSet.contains($0) } }

    // Common unit keywords across several languages
    let yearTokens = [
        // TR / EN / DE
        "yıl", "year", "years", "yr", "yrs", "jahr", "jahre", "jahren",
        // ES / PT / FR / IT / NL / PL
        "año", "años", "ano", "anos", "an", "ans", "année", "années", "anno", "anni", "jaar", "jaren", "rok", "lata", "lat",
        // RU
        "год", "года", "лет",
        // AR
        "سنة", "سنوات", "عام", "أعوام",
        // JA / ZH (CJK)
        "年"
    ]
    let monthTokens = [
        "ay", "month", "months", "monat", "monate", "monaten",
        "mes", "meses", "mois", "mese", "mesi", "miesiąc", "miesiące", "miesiecy",
        "месяц", "месяца", "месяцев", "شهر", "أشهر", "月"
    ]
    let weekTokens = [
        "hafta", "week", "weeks", "woche", "wochen",
        "semana", "semanas", "semaine", "semaines", "settimana", "settimane",
        "неделя", "недели", "недель", "週間", "周"
    ]
    let dayTokens = [
        "gün", "day", "days", "tag", "tagen",
        "día", "días", "jour", "jours", "giorno", "giorni",
        "день", "дня", "дней", "日", "天"
    ]
    let hourTokens = [
        "saat", "hour", "hours", "stunde", "stunden",
        "hora", "horas", "heure", "heures", "ora", "ore",
        "час", "часа", "часов", "時", "小时"
    ]
    let minuteTokens = [
        "dakika", "minute", "minutes", "min", "minuten",
        "minuto", "minuti", "minutos", "минута", "минуты", "минут", "分", "分钟"
    ]

    // Determine the unit in a safe order (year -> minute).
    // Uses exact word matching to avoid substring false positives.
    let unit: Calendar.Component? =
        has(yearTokens) ? .year :
        has(monthTokens) ? .month :
        has(weekTokens) ? .weekOfYear :
        has(dayTokens) ? .day :
        has(hourTokens) ? .hour :
        has(minuteTokens) ? .minute : nil
    guard let comp = unit else { return nil }
    guard let date = Calendar.current.date(byAdding: comp, value: -n, to: Date()) else { return nil }
    let df = ISO8601DateFormatter()
    df.formatOptions = [.withInternetDateTime]
    return df.string(from: date)
}

// MARK: - Absolute date parsing (e.g., "Sep 11, 2025")
/// Convert common absolute date strings to ISO8601 date string (UTC midnight).
/// Supported examples:
///  - EN: "MMM d, yyyy" (e.g., "Sep 11, 2025"), "MMMM d, yyyy" (e.g., "September 11, 2025")
///  - TR: "d MMM yyyy" (e.g., "11 Eyl 2025"), "d MMMM yyyy" (e.g., "11 Eylül 2025")
/// Returns nil when not recognized.
func absoluteDateToISO(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    // Already ISO-like (yyyy-MM-dd)
    if trimmed.count >= 10, trimmed.contains("-") {
        return String(trimmed.prefix(10)) + "T00:00:00Z"
    }
    let en = Locale(identifier: "en_US_POSIX")
    let tr = Locale(identifier: "tr_TR")
    let fmtsEN = ["MMM d, yyyy", "MMMM d, yyyy"]
    let fmtsTR = ["d MMM yyyy", "d MMMM yyyy"]
    let candidates: [(String, Locale)] = fmtsEN.map { ($0, en) } + fmtsTR.map { ($0, tr) }
    for (fmt, loc) in candidates {
        let df = DateFormatter()
        df.locale = loc
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = fmt
        if let d = df.date(from: trimmed) {
            let cal = Calendar(identifier: .gregorian)
            let midnight = cal.date(bySettingHour: 0, minute: 0, second: 0, of: d) ?? d
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime]
            return iso.string(from: midnight)
        }
    }
    return nil
}

// MARK: - Duration helpers
/// Convert a YouTube-style duration string like "9:58" or "1:02:03" into seconds.
func durationTextToSeconds(_ text: String) -> Int? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.contains(":") else { return nil }
    let parts = trimmed.split(separator: ":").compactMap { Int($0) }
    guard !parts.isEmpty else { return nil }
    // Support mm:ss or hh:mm:ss
    if parts.count == 2 {
        return parts[0] * 60 + parts[1]
    } else if parts.count == 3 {
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    } else {
        return nil
    }
}

/// Heuristic: Treat as "short" if duration is known and < 60 seconds.
/// Returns true only when we can confidently say it's under 60s.
func isUnderOneMinute(_ v: YouTubeVideo) -> Bool {
    if let secs = v.durationSeconds { return secs < 60 }
    if let secs = durationTextToSeconds(v.durationText) { return secs < 60 }
    return false
}

// MARK: - Central normalization helpers (single source of truth)
/// Normalize any viewCount text into a consistent localized display using formatViewCount.
/// Accepts raw strings like "1.2K", "123.456 görüntüleme", or placeholders. Returns a stable label.
func normalizeViewCountText(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }
    // Prefer approximate parsing first (e.g., 1.2K, 3,4M, 2 Mn), fallback to digits-only, else keep original
    if let approx = approxNumberFromText(trimmed) {
        return formatViewCount(String(approx))
    }
    let digits = String(trimmed.filter { $0.isNumber })
    return digits.isEmpty ? formatViewCount(trimmed) : formatViewCount(digits)
}

/// Normalize publishedAt display. If ISO provided use it; otherwise try absolute -> relative -> passthrough.
/// Returns (displayText, isoStringOptional)
func normalizePublishedDisplay(_ raw: String, iso: String? = nil) -> (String, String?) {
    // 1) If ISO known, display directly
    if let isoVal = iso, !isoVal.isEmpty { return (formatDate(isoVal), isoVal) }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return ("", nil) }
    // 2) Try absolute date patterns (e.g., "11 Eyl 2025", "Sep 11, 2025", or yyyy-MM-dd)
    if let absISO = absoluteDateToISO(trimmed) { return (formatDate(absISO), absISO) }
    // 3) Fallback: relative string (e.g., "5 gün önce", "3 weeks ago")
    if let relISO = relativeStringToISO(trimmed) { return (formatDate(relISO), relISO) }
    // 4) Unknown format -> return original as display, keep iso nil
    return (trimmed, nil)
}

// MARK: - Image/Avatar URL normalization (single source)
/// Normalize avatar/image URLs for consistent caching and https usage.
/// - Strips query parameters, converts // to https:, upgrades http to https.
/// - Leaves size hints embedded in the path (e.g., "=s88", "-no") intact.
func normalizeAvatarURL(_ raw: String) -> String {
    return ParsingUtils.normalizeURL(raw)
}

// MARK: - YouTube thumbnail helpers
enum YTThumbnailQuality: String {
    case defaultSmall = "default"     // 120x90
    case mqdefault = "mqdefault"      // 320x180
    case hqdefault = "hqdefault"      // 480x360
    case sddefault = "sddefault"      // 640x480
    case maxresdefault = "maxresdefault" // 1280x720
}

/// Build a stable i.ytimg.com thumbnail URL for a video id and desired quality.
func youtubeThumbnailURL(_ videoId: String, quality: YTThumbnailQuality = .mqdefault) -> String {
    return "https://i.ytimg.com/vi/\(videoId)/\(quality.rawValue).jpg"
}
