/*
 File Overview (EN)
 Purpose: Retrieve accurate channel subscriber counts via the official YouTube Data API.
 Key Responsibilities:
 - Call channels.list with statistics part for given channel IDs
 - Parse response and map subscriberCount to internal Channel model
 - Fallback gracefully when API key or permissions are missing
 Used By: SubscriberCountIntegration and channel detail enrichment.

 Dosya Özeti (TR)
 Amacı: Resmi YouTube Data API ile doğru kanal abone sayılarını almak.
 Ana Sorumluluklar:
 - Belirli kanal kimlikleri için statistics bölümüyle channels.list çağırmak
 - Yanıtı ayrıştırıp subscriberCount değerini iç Kanal modeline aktarmak
 - API anahtarı veya izinler yoksa zarifçe geri çekilmek
 Nerede Kullanılır: SubscriberCountIntegration ve kanal detayı zenginleştirme.
*/

import Foundation

// Service responsible only for fetching subscriber counts from official YouTube Data API (v3)
// No caching: always performs live requests as per requirement.
// Usage: call fetchSubscriberCounts(for:) with up to 50 channel IDs (API limit) and merge results into UI models.
// You must provide an API key via environment variable YT_API_KEY or set YouTubeAPIService.youtubeAPIKey before calling.

struct OfficialYouTubeSubscriberService {
    enum ServiceError: Error { case apiKeyMissing, invalidURL, requestFailed, decodingFailed }

    struct ChannelStatisticsResponse: Decodable {
        struct Item: Decodable { let id: String; let statistics: Statistics?; let snippet: Snippet? }
        struct Statistics: Decodable { let subscriberCount: String? }
        struct Snippet: Decodable { let title: String? }
        let items: [Item]
    }

    let apiKeyProvider: () -> String?
    init(apiKeyProvider: @escaping () -> String?) { self.apiKeyProvider = apiKeyProvider }

    // Fetch subscriber counts for up to 50 channel IDs.
    func fetchSubscriberCounts(for channelIds: [String]) async throws -> [String: Int] {
        let ids = channelIds.filter { !$0.isEmpty }
        guard !ids.isEmpty else { return [:] }
        guard let key = apiKeyProvider(), !key.isEmpty else { throw ServiceError.apiKeyMissing }
        // Build URL
        let joined = ids.joined(separator: ",")
        var comps = URLComponents(string: "https://www.googleapis.com/youtube/v3/channels")
        comps?.queryItems = [
            URLQueryItem(name: "part", value: "statistics"),
            URLQueryItem(name: "id", value: joined),
            URLQueryItem(name: "key", value: key)
        ]
        guard let url = comps?.url else { throw ServiceError.invalidURL }
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw ServiceError.requestFailed }
        guard let decoded = try? JSONDecoder().decode(ChannelStatisticsResponse.self, from: data) else { throw ServiceError.decodingFailed }
        var result: [String: Int] = [:]
        for item in decoded.items {
            if let raw = item.statistics?.subscriberCount, let val = Int(raw) { result[item.id] = val }
        }
        return result
    }
}
