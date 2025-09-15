/*
 File Overview (EN)
 Purpose: Core data models for YouTube entities: Video, Channel, Playlist, and Comment with Codable support.
 Key Responsibilities:
 - Define strongly-typed models with backward-compatible decoding
 - Provide convenience formatters (e.g., subscriber/like counts) and placeholders
 - Support optional fields like publishedAtISO and durationSeconds
 Used By: Almost every view/service rendering or fetching YouTube data.

 Dosya Özeti (TR)
 Amacı: YouTube varlıkları için temel veri modelleri: Video, Kanal, Oynatma Listesi ve Yorum (Codable destekli).
 Ana Sorumluluklar:
 - Eski verilerle uyumlu decode yapan güçlü tipler tanımlamak
 - Kolay biçimlendiriciler (abone/beğeni sayıları) ve placeholder üreticiler sunmak
 - publishedAtISO ve durationSeconds gibi opsiyonel alanları desteklemek
 Nerede Kullanılır: YouTube verisini getiren veya gösteren neredeyse tüm view/servisler.
*/


import Foundation

// YouTube Video Modeli
struct YouTubeVideo: Identifiable, Codable {
    let id: String
    let title: String
    let channelTitle: String
    let channelId: String
    let viewCount: String
    let publishedAt: String
    // Orijinal ISO tarih (sıralama için tutulur)
    let publishedAtISO: String?
    let thumbnailURL: String
    let description: String
    let channelThumbnailURL: String // Kanal profil fotoğrafı için eklendi
    let likeCount: String // Video beğeni sayısı
    let durationText: String  // "12:34" gibi
    let durationSeconds: Int? // ham saniye (opsiyonel)

    // Backward compatibility için init
    init(id: String, title: String, channelTitle: String, channelId: String, viewCount: String, publishedAt: String, publishedAtISO: String? = nil, thumbnailURL: String, description: String, channelThumbnailURL: String, likeCount: String = "0", durationText: String = "", durationSeconds: Int? = nil) {
        self.id = id
        self.title = title
        self.channelTitle = channelTitle
        self.channelId = channelId
        self.viewCount = viewCount
        self.publishedAt = publishedAt
        self.publishedAtISO = publishedAtISO
        self.thumbnailURL = thumbnailURL
        self.description = description
        self.channelThumbnailURL = channelThumbnailURL
        self.likeCount = likeCount
        self.durationText = durationText
        self.durationSeconds = durationSeconds
    }

    // Eski kayıtlarda likeCount veya publishedAtISO olmayabilir – güvenli decode
    enum CodingKeys: String, CodingKey {
        case id, title, channelTitle, channelId, viewCount, publishedAt, publishedAtISO, thumbnailURL, description, channelThumbnailURL, likeCount, durationText, durationSeconds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        channelTitle = try c.decode(String.self, forKey: .channelTitle)
        channelId = (try? c.decode(String.self, forKey: .channelId)) ?? ""
        viewCount = (try? c.decode(String.self, forKey: .viewCount)) ?? ""
        publishedAt = (try? c.decode(String.self, forKey: .publishedAt)) ?? ""
        publishedAtISO = try? c.decode(String.self, forKey: .publishedAtISO)
        thumbnailURL = (try? c.decode(String.self, forKey: .thumbnailURL)) ?? ""
        description = (try? c.decode(String.self, forKey: .description)) ?? ""
        channelThumbnailURL = (try? c.decode(String.self, forKey: .channelThumbnailURL)) ?? ""
        likeCount = (try? c.decode(String.self, forKey: .likeCount)) ?? "0"
    durationText = (try? c.decode(String.self, forKey: .durationText)) ?? ""
    durationSeconds = try? c.decode(Int.self, forKey: .durationSeconds)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(channelTitle, forKey: .channelTitle)
        try c.encode(channelId, forKey: .channelId)
        try c.encode(viewCount, forKey: .viewCount)
        try c.encode(publishedAt, forKey: .publishedAt)
        try c.encodeIfPresent(publishedAtISO, forKey: .publishedAtISO)
        try c.encode(thumbnailURL, forKey: .thumbnailURL)
        try c.encode(description, forKey: .description)
        try c.encode(channelThumbnailURL, forKey: .channelThumbnailURL)
        try c.encode(likeCount, forKey: .likeCount)
    if !durationText.isEmpty { try c.encode(durationText, forKey: .durationText) }
    try c.encodeIfPresent(durationSeconds, forKey: .durationSeconds)
    }
}

extension YouTubeVideo {
    /// Build a minimal placeholder video with only id (used to swap overlay panel quickly before metadata loads)
    static func makePlaceholder(id: String, title: String = "Video") -> YouTubeVideo {
        return YouTubeVideo(
            id: id,
            title: title,
            channelTitle: "",
            channelId: "",
            viewCount: "",
            publishedAt: "",
            publishedAtISO: nil,
            thumbnailURL: youtubeThumbnailURL(id, quality: .mqdefault),
            description: "",
            channelThumbnailURL: "",
            likeCount: "0",
            durationText: "",
            durationSeconds: nil
        )
    }
    var publishedAtISODate: Date? {
        guard let publishedAtISO else { return nil }
        // ISO8601DateFormatter hızlı; fallback normal DateFormatter
        let isoFormatter = ISO8601DateFormatter()
        if let d = isoFormatter.date(from: publishedAtISO) { return d }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        return fmt.date(from: publishedAtISO)
    }
}

struct YouTubeChannel: Identifiable, Codable {
    let id: String
    let title: String
    let description: String
    let thumbnailURL: String
    let bannerURL: String?
    let subscriberCount: Int
    let videoCount: Int
    
    // Formatted subscriber count
    var formattedSubscriberCount: String {
    let lang = UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.en.rawValue
    let suffix = (lang == AppLanguage.tr.rawValue) ? "abone" : "subscribers"
        if subscriberCount >= 1_000_000 {
            let millions = Double(subscriberCount) / 1_000_000
            if millions >= 10 {
        return String(format: "%.0fM %@", millions, suffix)
            } else {
        return String(format: "%.1fM %@", millions, suffix)
            }
        } else if subscriberCount >= 1_000 {
            let thousands = Double(subscriberCount) / 1_000
            if thousands >= 10 {
        return String(format: "%.0fK %@", thousands, suffix)
            } else {
        return String(format: "%.1fK %@", thousands, suffix)
            }
        } else {
        return "\(subscriberCount) \(suffix)"
        }
    }
    
    // Backward compatibility için init
    init(id: String, title: String, description: String, thumbnailURL: String, bannerURL: String? = nil, subscriberCount: Int = 0, videoCount: Int = 0) {
        self.id = id
        self.title = title
        self.description = description
        self.thumbnailURL = thumbnailURL
        self.bannerURL = bannerURL
        self.subscriberCount = subscriberCount
        self.videoCount = videoCount
    }
}

struct YouTubePlaylist: Identifiable, Codable {
    let id: String
    let title: String
    let description: String
    let thumbnailURL: String
    let videoCount: Int
    // Yerel içe aktarılan listeler için video ID'leri (opsiyonel; resmi YouTube listelerinde boş kalır)
    let videoIds: [String]?
    // Özel kapak görseli adı (örn. "playlist", "playlist2"), Examples klasöründen rastgele atanır
    let coverName: String?
    // Kullanıcının dosyadan yüklediği özel kapak (mutlak dosya yolu). coverName ile birlikte kullanılmaz.
    let customCoverPath: String?

    init(id: String, title: String, description: String = "", thumbnailURL: String = "", videoCount: Int = 0, videoIds: [String]? = nil, coverName: String? = nil, customCoverPath: String? = nil) {
        self.id = id
        self.title = title
        self.description = description
        self.thumbnailURL = thumbnailURL
        self.videoCount = videoCount
        self.videoIds = videoIds
        self.coverName = coverName
        self.customCoverPath = customCoverPath
    }

    enum CodingKeys: String, CodingKey { case id, title, description, thumbnailURL, videoCount, videoIds, coverName, customCoverPath }
}

class YouTubeComment: Identifiable, ObservableObject {
    let id: String
    let author: String
    let text: String
    let authorImage: String
    let likeCount: Int
    let publishedAt: String
    @Published var replyCount: Int
    let isPinned: Bool // Sabitlenmiş yorum için
    @Published var replies: [YouTubeComment]
    // Replies continuation token (local API)
    var repliesContinuationToken: String?
    
    // Formatted like count
    var formattedLikeCount: String {
        if likeCount >= 1_000_000 {
            let millions = Double(likeCount) / 1_000_000
            if millions >= 10 {
                return String(format: "%.0fM", millions)
            } else {
                return String(format: "%.1fM", millions)
            }
        } else if likeCount >= 1_000 {
            let thousands = Double(likeCount) / 1_000
            if thousands >= 10 {
                return String(format: "%.0fK", thousands)
            } else {
                return String(format: "%.1fK", thousands)
            }
        } else {
            return "\(likeCount)"
        }
    }
    
    // Backward compatibility için init
    init(id: String, author: String, text: String, authorImage: String, likeCount: Int = 0, publishedAt: String = "", replyCount: Int = 0, isPinned: Bool = false, replies: [YouTubeComment] = []) {
        self.id = id
        self.author = author
        self.text = text
        self.authorImage = authorImage
        self.likeCount = likeCount
        self.publishedAt = publishedAt
        self.replyCount = replyCount
        self.isPinned = isPinned
        self.replies = replies
        self.repliesContinuationToken = nil
    }

    // Codable support: Coding keys and Decodable initializer must live in the class
    enum CodingKeys: String, CodingKey {
        case id
        case author
        case text
        case authorImage
        case likeCount
        case publishedAt
        case replyCount
        case isPinned
        case replies
        case repliesContinuationToken
    }

    required convenience init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(String.self, forKey: .id)
        let author = try c.decode(String.self, forKey: .author)
        let text = try c.decode(String.self, forKey: .text)
        let authorImage = (try? c.decode(String.self, forKey: .authorImage)) ?? ""
        let likeCount = (try? c.decode(Int.self, forKey: .likeCount)) ?? 0
        let publishedAt = (try? c.decode(String.self, forKey: .publishedAt)) ?? ""
        let replyCount = (try? c.decode(Int.self, forKey: .replyCount)) ?? 0
        let isPinned = (try? c.decode(Bool.self, forKey: .isPinned)) ?? false
        let replies = (try? c.decode([YouTubeComment].self, forKey: .replies)) ?? []
        self.init(id: id, author: author, text: text, authorImage: authorImage, likeCount: likeCount, publishedAt: publishedAt, replyCount: replyCount, isPinned: isPinned, replies: replies)
        self.repliesContinuationToken = try? c.decode(String.self, forKey: .repliesContinuationToken)
    }
}

// Make comments codable so we can cache them to disk
extension YouTubeComment: Codable {
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(author, forKey: .author)
        try c.encode(text, forKey: .text)
        try c.encode(authorImage, forKey: .authorImage)
        try c.encode(likeCount, forKey: .likeCount)
        try c.encode(publishedAt, forKey: .publishedAt)
        try c.encode(replyCount, forKey: .replyCount)
        try c.encode(isPinned, forKey: .isPinned)
        try c.encode(replies, forKey: .replies)
        try c.encodeIfPresent(repliesContinuationToken, forKey: .repliesContinuationToken)
    }
}
