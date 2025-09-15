
/*
 File Overview (EN)
 Purpose: Shared data structures and simple wrappers used by the lightweight caching layer (disk/in-memory).
 Key Responsibilities:
 - Define Codable models for cached payloads and keys
 - Provide small helpers/constants reused across CacheStore and others
 - Keep cache types centralized to avoid duplication across services
 Used By: Services/Cache/CacheStore, PlaybackProgressStore, and various services reading cached data.

 Dosya Özeti (TR)
 Amacı: Hafif önbellek katmanında (disk/bellek) kullanılan ortak veri yapıları ve basit sarmalayıcıları barındırır.
 Ana Sorumluluklar:
 - Önbelleğe alınan yükler ve anahtarlar için Codable modeller tanımlamak
 - CacheStore ve diğerlerinde paylaşılan küçük yardımcılar/sabitler sağlamak
 - Önbellek türlerini merkezileştirerek servisler arası tekrarları azaltmak
 Nerede Kullanılır: Services/Cache/CacheStore, PlaybackProgressStore ve önbellekten okuma yapan servisler.
*/

import Foundation
import CryptoKit

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

public struct CachePolicy {
    public static func expiryDate(ttl: TimeInterval) -> Date { Date().addingTimeInterval(ttl) }
}

public struct CacheKey {
    public let raw: String
    public init(_ raw: String) { self.raw = raw }
    public func hashedFilename(extension ext: String = "json") -> String {
        let digest = SHA256.hash(data: Data(raw.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(hex).\(ext)"
    }
}

public struct CacheEnvelope<T: Codable>: Codable {
    public let value: T
    public let expiry: Date
}
