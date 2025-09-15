/*
 Overview / Genel Bakış
 EN: Core models for YouTube entities (Video, Channel, Playlist, Comment) with Codable and graceful backward-compat decoding.
 TR: YouTube varlıkları için temel modeller (Video, Kanal, Liste, Yorum); Codable ve geriye dönük uyumlu decode içerir.
*/


// EN: Foundation for Codable, Date parsing, etc. TR: Codable, Tarih ayrıştırma vb. için Foundation.
import Foundation

// EN: YouTube video model used across views/services. TR: Görünümler/servislerde kullanılan YouTube video modeli.
struct YouTubeVideo: Identifiable, Codable {
    // EN: Unique id (YT video id). TR: Benzersiz kimlik (YT video id).
    let id: String
    // EN: Video title. TR: Video başlığı.
    let title: String
    // EN: Channel display name. TR: Kanal görünen adı.
    let channelTitle: String
    // EN: Channel id (for navigation). TR: Kanal id'si (gezinme için).
    let channelId: String
    // EN: Raw view count text (as scraped/API). TR: Ham izlenme metni (toplanan/APİ).
    let viewCount: String
    // EN: Human readable publish label. TR: İnsan okuyabilir yayınlanma etiketi.
    let publishedAt: String
    // EN: Original ISO date for sorting. TR: Sıralama için tutulan orijinal ISO tarih.
    let publishedAtISO: String?
    // EN: Thumbnail URL (may be normalized later). TR: Küçük resim URL'si (sonradan normalize edilebilir).
    let thumbnailURL: String
    // EN: Video description text. TR: Video açıklaması.
    let description: String
    // EN: Channel avatar URL. TR: Kanal profil foto URL'si.
    let channelThumbnailURL: String
    // EN: Like count string. TR: Beğeni sayısı metni.
    let likeCount: String
    // EN: Duration in text, e.g. "12:34". TR: Metin süre, örn. "12:34".
    let durationText: String
    // EN: Raw duration in seconds (optional). TR: Ham süre saniye (opsiyonel).
    let durationSeconds: Int?

    // EN: Init with defaults for backward compatibility. TR: Geriye uyumluluk için varsayılanlarla init.
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

    // EN: Older records may miss likeCount/publishedAtISO – decode safely. TR: Eski kayıtlarda likeCount/publishedAtISO olmayabilir – güvenli decode.
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
    // EN: Parse ISO string into Date (fast ISO8601 then fallback). TR: ISO dizgesini Date'e çevir (hızlı ISO8601 sonra yedek).
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

// EN: YouTube channel summary model. TR: YouTube kanal özet modeli.
struct YouTubeChannel: Identifiable, Codable {
    // EN: Channel id. TR: Kanal id'si.
    let id: String
    // EN: Channel title. TR: Kanal başlığı.
    let title: String
    // EN: Channel description. TR: Kanal açıklaması.
    let description: String
    // EN: Channel avatar URL. TR: Kanal avatar URL'si.
    let thumbnailURL: String
    // EN: Optional banner image. TR: Opsiyonel banner görseli.
    let bannerURL: String?
    // EN: Subscriber count (int). TR: Abone sayısı (int).
    let subscriberCount: Int
    // EN: Total videos in channel. TR: Kanaldaki toplam video.
    let videoCount: Int
    
    // EN: Localized formatted subscriber label. TR: Yerelleştirilmiş abone etiketi.
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
    
    // EN: Init with defaults for backward compatibility. TR: Geriye uyum için varsayılanlara sahip init.
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

// EN: Playlist model (supports local/imported lists). TR: Oynatma listesi modeli (yerel/ithal listeleri destekler).
struct YouTubePlaylist: Identifiable, Codable {
    // EN: Playlist id. TR: Liste id'si.
    let id: String
    // EN: Playlist title. TR: Liste başlığı.
    let title: String
    // EN: Optional description. TR: Opsiyonel açıklama.
    let description: String
    // EN: Thumbnail URL or custom cover. TR: Küçük resim URL'si veya özel kapak.
    let thumbnailURL: String
    // EN: Number of videos. TR: Video sayısı.
    let videoCount: Int
    // EN: Video ids for locally imported lists (optional). TR: Yerel içe aktarılan listeler için video id'leri (ops.).
    let videoIds: [String]?
    // EN: Optional sample cover from Examples. TR: Examples klasöründen opsiyonel kapak adı.
    let coverName: String?
    // EN: User-chosen custom cover path (mutually exclusive with coverName). TR: Kullanıcı seçimi özel kapak yolu (coverName ile birlikte kullanılmaz).
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

    // EN: Explicit coding keys to keep stable serialization. TR: Kararlı serileştirme için açık coding keys.
    enum CodingKeys: String, CodingKey { case id, title, description, thumbnailURL, videoCount, videoIds, coverName, customCoverPath }
}

// EN: Observable, codable comment thread node. TR: Gözlemlenebilir, kodlanabilir yorum düğümü.
class YouTubeComment: Identifiable, ObservableObject {
    // EN: Comment id. TR: Yorum id'si.
    let id: String
    // EN: Author display name. TR: Yazar görünen adı.
    let author: String
    // EN: Comment text. TR: Yorum metni.
    let text: String
    // EN: Author avatar URL. TR: Yazar avatar URL'si.
    let authorImage: String
    // EN: Like count. TR: Beğeni sayısı.
    let likeCount: Int
    // EN: Human readable publish time. TR: İnsan okuyabilir yayın zamanı.
    let publishedAt: String
    // EN: Number of replies (observable). TR: Yanıt sayısı (gözlemlenir).
    @Published var replyCount: Int
    // EN: Pinned flag. TR: Sabitlenmiş yorum bayrağı.
    let isPinned: Bool
    // EN: Replies (observable). TR: Yanıtlar (gözlemlenir).
    @Published var replies: [YouTubeComment]
    // EN: Continuation token to fetch more replies. TR: Daha fazla yanıtı çekmek için devam jetonu.
    var repliesContinuationToken: String?
    
    // EN: Localized short like count label. TR: Yerelleştirilmiş kısa beğeni etiketi.
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
    
    // EN: Init with defaults for backward compatibility. TR: Geriye uyumluluk için varsayılanlarla init.
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

    // EN: Codable: coding keys and Decodable convenience init. TR: Codable: coding keys ve Decodable convenience init.
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

// EN: Make comments encodable for disk caching. TR: Disk önbelleği için yorumları encodable yap.
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
