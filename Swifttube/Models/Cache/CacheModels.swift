/*
 Overview / Genel Bakış
 EN: Shared cache data types: TTLs, cache keys with hashed filenames, policies, and generic envelope for values with expiry.
 TR: Ortak önbellek türleri: TTL sabitleri, hash'li dosya adları olan anahtarlar, politikalar ve süresi dolumlu genel zarf.
*/

// EN: Foundation for Date/TimeInterval, CryptoKit for SHA256. TR: Tarih/Zaman için Foundation, SHA256 için CryptoKit.
import Foundation
import CryptoKit

// EN: Common TTL presets for cache entries. TR: Önbellek girişleri için yaygın TTL değerleri.
public enum CacheTTL {
    public static let fiveMinutes: TimeInterval = 5 * 60
    public static let thirtyMinutes: TimeInterval = 30 * 60
    public static let oneHour: TimeInterval = 60 * 60
    public static let sixHours: TimeInterval = 6 * 60 * 60
    public static let eightHours: TimeInterval = 8 * 60 * 60
    public static let twelveHours: TimeInterval = 12 * 60 * 60
    public static let oneDay: TimeInterval = 24 * 60 * 60
    public static let sevenDays: TimeInterval = 7 * 24 * 60 * 60
}

// EN: Simple policy helper to compute expiry Date from TTL. TR: TTL'den son kullanma tarihini hesaplayan yardımcı.
public struct CachePolicy {
    public static func expiryDate(ttl: TimeInterval) -> Date { Date().addingTimeInterval(ttl) }
}

// EN: Stable cache key with SHA256-based filename generator. TR: SHA256 tabanlı dosya adı üreten sağlam önbellek anahtarı.
public struct CacheKey {
    public let raw: String
    public init(_ raw: String) { self.raw = raw }
    public func hashedFilename(extension ext: String = "json") -> String {
        let digest = SHA256.hash(data: Data(raw.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(hex).\(ext)"
    }
}

// EN: Generic value+expiry envelope to store typed payloads. TR: Tipli yükleri saklamak için genel değer+son kullanma zarfı.
public struct CacheEnvelope<T: Codable>: Codable {
    public let value: T
    public let expiry: Date
}
