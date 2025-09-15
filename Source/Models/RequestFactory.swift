/*
 Overview / Genel Bakış
 EN: Central HTTP defaults and builders for YouTube HTML endpoints (UA, Accept-Language, Cookie, Encoding).
 TR: YouTube HTML uçları için merkezi HTTP varsayılanları ve üreticiler (UA, Accept-Language, Cookie, Encoding).
*/

import Foundation

/// Tek noktadan HTTP istek varsayılanları (User-Agent, Accept-Language, Cookie, Accept-Encoding).
enum RequestFactory {
    /// EN: Realistic Safari-based UA (keeps scraper behavior stable). TR: Gerçekçi Safari tabanlı UA (kazıma davranışını sabit tutar).
    static let defaultUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 13_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    /// EN: Default Accept-Language (fixed en-US to stabilize results). TR: Varsayılan Accept-Language (sonuçları sabitlemek için en-US).
    static let defaultAcceptLanguage = "en-US,en;q=0.9"

    /// EN: Default Accept-Encoding. TR: Varsayılan Accept-Encoding.
    static let defaultAcceptEncoding = "gzip, deflate, br"

    /// EN: Build Cookie header including SOCS/CONSENT and PREF with hl/gl. TR: SOCS/CONSENT ve PREF (hl/gl) içeren Cookie başlığı oluştur.
    static func cookieHeaderValue(hl: String? = "en", gl: String? = "US") -> String {
        let lang = (hl?.isEmpty == false) ? hl! : "en"
        if let region = gl, !region.isEmpty {
            return "SOCS=CAI; CONSENT=YES+; PREF=hl=\(lang)&gl=\(region)"
        } else {
            return "SOCS=CAI; CONSENT=YES+; PREF=hl=\(lang)"
        }
    }

    /// EN: Build a URLRequest for YouTube HTML endpoints with defaults; override hl/gl/UA if needed. TR: YouTube HTML uçları için varsayılanlarla URLRequest üret; gerekirse hl/gl/UA geçersiz kıl.
    static func makeYouTubeHTMLRequest(url: URL, hl: String? = "en", gl: String? = "US", userAgentOverride: String? = nil) -> URLRequest {
        var req = URLRequest(url: url)
        req.setValue(userAgentOverride ?? defaultUserAgent, forHTTPHeaderField: "User-Agent")
        req.setValue(defaultAcceptLanguage, forHTTPHeaderField: "Accept-Language")
        req.setValue(cookieHeaderValue(hl: hl, gl: gl), forHTTPHeaderField: "Cookie")
        req.setValue(defaultAcceptEncoding, forHTTPHeaderField: "Accept-Encoding")
        return req
    }
}
