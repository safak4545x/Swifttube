/*
 Overview / Genel Bakış
 EN: Reusable helpers and extensions: safe subscripts, clamping, count/date formatting, parsing, and URL normalization.
 TR: Yeniden kullanılabilir yardımcılar ve uzatmalar: güvenli subscript, clamp, sayı/tarih formatlama, ayrıştırma ve URL normalizasyonu.
*/

// EN: Foundation for Date/Locale/Regex utilities. TR: Tarih/Dil/Regex yardımcıları için Foundation.
import Foundation

// EN: Safe index access for any Collection. TR: Herhangi bir Collection için güvenli indeks erişimi.
extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// EN: Clamp a comparable value to a range. TR: Karşılaştırılabilir bir değeri aralığa sıkıştır (clamp).
extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        if self < limits.lowerBound { return limits.lowerBound }
        if self > limits.upperBound { return limits.upperBound }
        return self
    }
}

// EN: Format a view count string with localized suffix. TR: Görüntülenme sayısını yerelleştirilmiş son ek ile biçimlendir.
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

// EN: Short count format (number only) e.g., 987, 1.2K, 3.4M, 1.1B. TR: Kısa sayı formatı (sadece sayı) örn: 987, 1.2K, 3.4M, 1.1B.
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

// EN: Parse approximate number from localized strings (e.g., 1.2K, 3,4M, 2 Mn, 12 B, 123.456). Returns best-effort integer.
// TR: Yerelleştirilmiş metinden yaklaşık sayı ayrıştır (örn. 1.2K, 3,4M, 2 Mn, 12 B, 123.456). En makul tam sayıyı döndürür.
func approxNumberFromText(_ text: String) -> Int? {
    let s = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !s.isEmpty else { return nil }

    // EN: 1) Grouped digits: 1.234.567 / 1,234,567 / 1 234 567. TR: 1) Binlik gruplama: 1.234.567 / 1,234,567 / 1 234 567.
    if let re = try? NSRegularExpression(pattern: #"(?<!\d)(\d{1,3}(?:[\.,\s]\d{3})+)(?!\d)"#, options: []),
       let m = re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)), m.numberOfRanges > 1 {
        let r = m.range(at: 1)
        if r.location != NSNotFound, let rr = Range(r, in: s) {
            let token = String(s[rr])
            let cleaned = token.replacingOccurrences(of: #"[\s\.,]"#, with: "", options: .regularExpression)
            if let n = Int(cleaned) { return n }
        }
    }

    // EN: 2) Suffix-based numbers: 1.2K, 3,4M, 2 Mn, 1B. TR: 2) Sonekli sayılar: 1.2K, 3,4M, 2 Mn, 1B.
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

    // EN: 3) Plain integer digits (e.g., 51552). TR: 3) Düz rakamlar (örn: 51552).
    if let re = try? NSRegularExpression(pattern: #"(?<!\d)(\d{2,})(?!\d)"#, options: []),
       let m = re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)), m.numberOfRanges > 1 {
        let ns = s as NSString
        if let n = Int(ns.substring(with: m.range(at: 1))) { return n }
    }

    return nil
}

// EN: Format an ISO8601 date string into a relative “time ago” label (localized). TR: ISO8601 tarih dizgesini yerelleştirilmiş "önce" etiketine çevir.
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

    // EN: Helper to format singular/plural units per language. TR: Dile göre tekil/çoğul birim formatlayan yardımcı.
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

// MARK: - Relative date parsing (language-agnostic input -> ISO8601) / Göreli tarih ayrıştırma
/// Convert a localized relative time string (e.g., "5 days ago", "3 yıl önce", "vor 2 Jahren",
/// "hace 2 años", "il y a 3 mois", "2 недели назад") to an ISO8601 date string.
/// The output is purely date math and does not depend on device region; use formatDate(_) to display.
// EN: Convert localized relative time (e.g., "5 days ago", "3 yıl önce") to ISO8601 date. TR: Yerelleştirilmiş göreli zamanı (örn. "3 yıl önce") ISO8601'e çevir.
func relativeStringToISO(_ raw: String) -> String? {
    let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !lower.isEmpty else { return nil }
    // Extract first integer from the string (supports all Unicode digits)
    let digits = String(lower.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) })
    guard let n = Int(digits), n > 0 else { return nil }

    // EN: Tokenize by unicode letters to match whole words; avoids collisions like TR "ay" vs EN "days".
    // TR: Unicode harflerle böl, tam kelime eşleşmesi olsun; TR "ay" ile EN "days" çakışmasını önler.
    let wordSeparator = CharacterSet.letters.inverted
    let words = lower.components(separatedBy: wordSeparator).filter { !$0.isEmpty }
    let wordSet = Set(words)
    // Helper to test if any of the tokens appear as whole words
    func has(_ tokens: [String]) -> Bool { tokens.contains { wordSet.contains($0) } }

    // EN: Common unit tokens across languages. TR: Birçok dilde ortak birim anahtarları.
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

    // EN: Detect unit in safe order (year → minute) using whole-word matches. TR: Tam kelime eşleşmesiyle güvenli sırada birimi bul (yıl → dakika).
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

// MARK: - Absolute date parsing (e.g., "Sep 11, 2025") / Mutlak tarih ayrıştırma
/// Convert common absolute date strings to ISO8601 date string (UTC midnight).
/// Supported examples:
///  - EN: "MMM d, yyyy" (e.g., "Sep 11, 2025"), "MMMM d, yyyy" (e.g., "September 11, 2025")
///  - TR: "d MMM yyyy" (e.g., "11 Eyl 2025"), "d MMMM yyyy" (e.g., "11 Eylül 2025")
/// Returns nil when not recognized.
// EN: Convert common absolute dates (EN/TR) to ISO8601 midnight UTC. TR: Yaygın mutlak tarihleri (EN/TR) ISO8601 gece yarısı UTC'ye çevir.
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

// MARK: - Duration helpers / Süre yardımcıları
/// Convert a YouTube-style duration string like "9:58" or "1:02:03" into seconds.
// EN: Convert "mm:ss" or "hh:mm:ss" to seconds. TR: "dd:ss" veya "ss:dd:ss" biçimini saniyeye çevir.
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
// EN: Heuristic: determine if a video is < 60s using known fields. TR: Sezgisel: bilinen alanlarla videonun < 60 sn olup olmadığını belirle.
func isUnderOneMinute(_ v: YouTubeVideo) -> Bool {
    if let secs = v.durationSeconds { return secs < 60 }
    if let secs = durationTextToSeconds(v.durationText) { return secs < 60 }
    return false
}

// MARK: - Central normalization helpers (single source of truth) / Merkezileştirilmiş normalizasyon yardımcıları
/// Normalize any viewCount text into a consistent localized display using formatViewCount.
/// Accepts raw strings like "1.2K", "123.456 görüntüleme", or placeholders. Returns a stable label.
// EN: Normalize any raw viewCount text to a stable localized label. TR: Her türlü viewCount metnini yerelleştirilmiş kararlı etikete normalleştir.
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
// EN: Normalize publishedAt display with ISO fallback chain. TR: publishedAt gösterimini ISO yedek zinciriyle normalleştir.
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

// MARK: - Image/Avatar URL normalization (single source) / Resim/Avatar URL normalizasyonu
/// Normalize avatar/image URLs for consistent caching and https usage.
/// - Strips query parameters, converts // to https:, upgrades http to https.
/// - Leaves size hints embedded in the path (e.g., "=s88", "-no") intact.
// EN: Normalize avatar/thumbnail URLs (https, strip query). TR: Avatar/küçük resim URL'lerini normalize et (https, query temizle).
func normalizeAvatarURL(_ raw: String) -> String {
    return ParsingUtils.normalizeURL(raw)
}

// MARK: - YouTube thumbnail helpers / YouTube küçük resim yardımcıları
// EN: Supported YouTube thumbnail qualities. TR: Desteklenen YouTube küçük resim kaliteleri.
enum YTThumbnailQuality: String {
    case defaultSmall = "default"     // 120x90
    case mqdefault = "mqdefault"      // 320x180
    case hqdefault = "hqdefault"      // 480x360
    case sddefault = "sddefault"      // 640x480
    case maxresdefault = "maxresdefault" // 1280x720
}

/// Build a stable i.ytimg.com thumbnail URL for a video id and desired quality.
// EN: Build a stable i.ytimg.com URL for given id and quality. TR: Verilen id ve kalite için sabit i.ytimg.com URL'si oluştur.
func youtubeThumbnailURL(_ videoId: String, quality: YTThumbnailQuality = .mqdefault) -> String {
    return "https://i.ytimg.com/vi/\(videoId)/\(quality.rawValue).jpg"
}
