/*
 Overview / Genel Bakış
 EN: Language utilities: resolve preferred UI language (hl), provide stopwords, and Shorts markers per language.
 TR: Dil yardımcıları: tercih edilen arayüz dili (hl) çözümü, stopword listeleri ve dile göre Shorts işaretleyicileri.
*/

import Foundation

/// Tek noktadan dil-bölge kaynakları: stopwords, shorts işaretleyiciler, bölge->hl tercihleri.
enum LanguageResources {
    // EN: Preferred UI language (hl) by region code; fallback to app language. TR: Bölge koduna göre tercih edilen arayüz dili (hl); yoksa uygulama diline düşer.
    static func preferredHL(for region: String?) -> String {
        guard let code = region, !code.isEmpty, code != "GLOBAL" else {
            // EN: Use app language as default (tr or en). TR: Varsayılan olarak uygulama dilini kullan (tr veya en).
            let appLang = UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.en.rawValue
            return (appLang == AppLanguage.tr.rawValue) ? "tr" : "en"
        }
        switch code.uppercased() {
        case "TR": return "tr"
        case "US", "GB", "CA", "AU", "NZ", "IE", "ZA", "PH", "IN", "NG", "KE", "GH", "TZ", "UG": return "en"
        case "DE", "AT", "CH": return "de"
        case "FR", "MA", "TN", "DZ": return "fr"
        case "ES", "MX", "AR", "CL", "CO", "PE", "VE", "UY", "PY", "BO", "EC", "GT", "CR", "PA", "DO", "PR": return "es"
        case "IT": return "it"
        case "PT", "BR": return "pt"
        case "RU": return "ru"
        case "UA": return "uk"
        case "PL": return "pl"
        case "CZ": return "cs"
        case "SK": return "sk"
        case "HU": return "hu"
        case "RO": return "ro"
        case "BG": return "bg"
        case "GR": return "el"
        case "NL", "BE", "LU": return "nl"
        case "SE": return "sv"
        case "NO": return "no"
        case "DK": return "da"
        case "FI": return "fi"
        case "JP": return "ja"
        case "KR": return "ko"
        case "CN", "TW", "HK": return "zh"
        case "ID": return "id"
        case "MY": return "ms"
        case "TH": return "th"
        case "VN": return "vi"
        case "IL": return "he"
        case "SA", "AE", "QA", "KW", "BH", "OM", "EG": return "ar"
        default: return "en"
        }
    }

    // EN: Stopword list by UI language (hl). TR: Arayüz diline (hl) göre stopword listesi.
    static func stopwords(for hl: String) -> Set<String> {
        switch hl {
        case "tr": return ["ve","ile","bir","bu","şu","o","için","mi","mu","mü","de","da","en","çok","az","ama","fakat","ya","ya da","ki","şimdi","gibi","yeni","son","ilk","neden"]
        case "es": return ["y","de","la","el","los","las","un","una","para","con","en","por","del","al","como"]
        case "de": return ["und","der","die","das","ein","eine","mit","für","ist","im","am","als","wie"]
        case "fr": return ["et","le","la","les","un","une","des","pour","avec","est","dans","sur","comme"]
        default: return ["and","the","a","an","for","with","on","in","of","to","is","are","new","best","top","how","why","what"]
        }
    }

    // EN: Shorts markers detected in titles per language. TR: Dile göre başlıklarda tespit edilen Shorts işaretleyicileri.
    static func shortsMarkers(for hl: String) -> [String] {
        let map: [String: [String]] = [
            "en": ["#shorts", "shorts", "short video"],
            "tr": ["#shorts", "shorts", "kısa video", "kısa"],
            "es": ["#shorts", "shorts", "video corto", "corto"],
            "de": ["#shorts", "shorts", "kurzvideo", "kurz"],
            "fr": ["#shorts", "shorts", "vidéo courte", "court"],
            "it": ["#shorts", "shorts", "video corto", "corto"],
            "pt": ["#shorts", "shorts", "vídeo curto", "curto"],
            "ru": ["#shorts", "shorts", "короткое видео", "короткие"],
            "uk": ["#shorts", "shorts", "коротке відео", "короткі"],
            "ar": ["#shorts", "shorts", "فيديو قصير"],
            "ja": ["#shorts", "shorts", "ショート", "短い動画"],
            "ko": ["#shorts", "shorts", "쇼츠", "짧은 영상"],
            "zh": ["#shorts", "shorts", "短视频", "短片"],
            "nl": ["#shorts", "shorts", "kort filmpje", "kort"],
            "pl": ["#shorts", "shorts", "krótkie wideo", "krótki"],
            "sv": ["#shorts", "shorts", "kort video", "kort"],
            "no": ["#shorts", "shorts", "kort video", "kort"],
            "da": ["#shorts", "shorts", "kort video", "kort"],
            "fi": ["#shorts", "shorts", "lyhyt video", "lyhyt"],
            "cs": ["#shorts", "shorts", "krátké video", "krátké"],
            "sk": ["#shorts", "shorts", "krátke video", "krátke"],
            "hu": ["#shorts", "shorts", "rövid videó", "rövid"],
            "ro": ["#shorts", "shorts", "video scurt", "scurt"],
            "bg": ["#shorts", "shorts", "кратко видео", "кратко"],
            "el": ["#shorts", "shorts", "σύντομο βίντεο", "σύντομο"],
            "id": ["#shorts", "shorts", "video pendek", "pendek"],
            "ms": ["#shorts", "shorts", "video pendek", "pendek"],
            "th": ["#shorts", "shorts", "วิดีโอสั้น", "สั้น"],
            "vi": ["#shorts", "shorts", "video ngắn", "ngắn"],
            "he": ["#shorts", "shorts"]
        ]
        return map[hl] ?? map["en"]!
    }
}
