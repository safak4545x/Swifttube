/*
 File Overview (EN)
 Purpose: Query the official YouTube Data API for playlist metadata (notably total item counts) when an API key is provided.
 Key Responsibilities:
 - Build playlists.list requests (part=contentDetails) for up to 50 playlist IDs
 - Decode responses and map itemCount to internal storage for UI display
 - Act as an optional enrichment for locally scraped playlist results
 Used By: YouTubeAPIService (SubscriberCountIntegration section) to fill totalPlaylistCountById.

 Dosya Özeti (TR)
 Amacı: Bir API anahtarı mevcutken resmi YouTube Data API üzerinden oynatma listesi (özellikle toplam öğe sayısı) bilgisini almak.
 Ana Sorumluluklar:
 - 50 adede kadar playlist ID için playlists.list (part=contentDetails) isteklerini kurmak
 - Yanıtı ayrıştırıp itemCount değerini iç depolamaya/arayüze yansıtmak
 - Yerel kazımayla bulunan sonuçları isteğe bağlı olarak zenginleştirmek
 Nerede Kullanılır: YouTubeAPIService (SubscriberCountIntegration kısmı) totalPlaylistCountById alanını doldurmak için.
*/

import Foundation

// Service for fetching playlist item counts via the official YouTube Data API v3
// Endpoint: playlists.list(part=contentDetails&id=...)
// itemCount is authoritative and works for large playlists.
// Provide API key via YouTubeAPIService.apiKey (persisted in settings).

struct OfficialYouTubePlaylistService {
    enum ServiceError: Error { case apiKeyMissing, invalidURL, requestFailed, decodingFailed }

    struct PlaylistsResponse: Decodable {
        struct Item: Decodable { let id: String; let contentDetails: ContentDetails? }
        struct ContentDetails: Decodable { let itemCount: Int? }
        let items: [Item]
    }

    let apiKeyProvider: () -> String?
    init(apiKeyProvider: @escaping () -> String?) { self.apiKeyProvider = apiKeyProvider }

    // Fetch playlist item counts for up to 50 playlist IDs at a time.
    func fetchItemCounts(for playlistIds: [String]) async throws -> [String: Int] {
        let ids = playlistIds.filter { !$0.isEmpty }
        guard !ids.isEmpty else { return [:] }
        guard let key = apiKeyProvider(), !key.isEmpty else { throw ServiceError.apiKeyMissing }
        var comps = URLComponents(string: "https://www.googleapis.com/youtube/v3/playlists")
        comps?.queryItems = [
            .init(name: "part", value: "contentDetails"),
            .init(name: "id", value: ids.joined(separator: ",")),
            .init(name: "maxResults", value: "50"),
            .init(name: "key", value: key)
        ]
        guard let url = comps?.url else { throw ServiceError.invalidURL }
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw ServiceError.requestFailed }
        do {
            let decoded = try JSONDecoder().decode(PlaylistsResponse.self, from: data)
            var out: [String: Int] = [:]
            for it in decoded.items { if let n = it.contentDetails?.itemCount { out[it.id] = n } }
            return out
        } catch {
            throw ServiceError.decodingFailed
        }
    }
}
