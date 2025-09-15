/*
 File Overview (EN)
 Purpose: Provide centralized HTTP request defaults (User-Agent, Accept-Language, Cookies, Encoding) and builders for YouTube HTML endpoints.
 Key Responsibilities:
 - Keep a Safari-like User-Agent and stable en-US Accept-Language for predictable scraping
 - Generate Cookie header with PREF/CONSENT to bypass dialogs and pin hl/gl
 - Offer helpers to construct URLRequest for HTML endpoints consistently
 Used By: Local adapters and services interacting with YouTube web pages.

 Dosya Özeti (TR)
 Amacı: HTTP istek varsayılanlarını (User-Agent, Accept-Language, Cookie, Encoding) merkezileştirip YouTube HTML uçları için istek üreticileri sağlamaktır.
 Ana Sorumluluklar:
 - Kazımanın tutarlı olması için Safari benzeri UA ve en-US Accept-Language kullanmak
 - PREF/CONSENT içeren Cookie başlığını üreterek diyalogları atlamak ve hl/gl sabitlemek
 - HTML uçları için URLRequest oluşturmayı tutarlı kılan yardımcılar sunmak
 Nerede Kullanılır: YouTube web sayfalarıyla çalışan yerel adaptörler ve servisler.
*/

import Foundation

/// Tek noktadan HTTP istek varsayılanları (User-Agent, Accept-Language, Cookie, Accept-Encoding).
enum RequestFactory {
    /// Safari tabanlı gerçekçi bir UA (mevcut kodla aynı)
    static let defaultUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 13_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    /// Varsayılan Accept-Language (davranışı korumak için sabit en-US)
    static let defaultAcceptLanguage = "en-US,en;q=0.9"

    /// Varsayılan Accept-Encoding
    static let defaultAcceptEncoding = "gzip, deflate, br"

    /// PREF hl/gl + consent bypass içeren Cookie header değeri üretir
    static func cookieHeaderValue(hl: String? = "en", gl: String? = "US") -> String {
        let lang = (hl?.isEmpty == false) ? hl! : "en"
        if let region = gl, !region.isEmpty {
            return "SOCS=CAI; CONSENT=YES+; PREF=hl=\(lang)&gl=\(region)"
        } else {
            return "SOCS=CAI; CONSENT=YES+; PREF=hl=\(lang)"
        }
    }

    /// YouTube HTML endpoint'leri için hazır URLRequest üretir (davranış: en/US sabit, istenirse override edilebilir)
    static func makeYouTubeHTMLRequest(url: URL, hl: String? = "en", gl: String? = "US", userAgentOverride: String? = nil) -> URLRequest {
        var req = URLRequest(url: url)
        req.setValue(userAgentOverride ?? defaultUserAgent, forHTTPHeaderField: "User-Agent")
        req.setValue(defaultAcceptLanguage, forHTTPHeaderField: "Accept-Language")
        req.setValue(cookieHeaderValue(hl: hl, gl: gl), forHTTPHeaderField: "Cookie")
        req.setValue(defaultAcceptEncoding, forHTTPHeaderField: "Accept-Encoding")
        return req
    }
}
