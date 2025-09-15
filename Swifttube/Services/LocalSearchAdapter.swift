
/*
 File Overview (EN)
 Purpose: Local search adapter that scrapes YouTube search results, producing lightweight YouTubeVideo models.
 Key Responsibilities:
 - Fetch /results HTML/JSON and parse titles, channel, views, published time, thumbnails, and duration
 - Normalize view counts and publishedAt via shared helpers; cache results with TTL
 Used By: VideoSearchService for local-only search flows.

 Dosya Özeti (TR)
 Amacı: YouTube arama sonuçlarını kazıyarak hafif YouTubeVideo modelleri üreten yerel arama adaptörü.
 Ana Sorumluluklar:
 - /results HTML/JSON içeriğini çekip başlık, kanal, görüntülenme, tarih, küçük resim ve süreyi ayrıştırmak
 - Görüntülenme ve tarihleri ortak yardımcılarla normalize etmek; sonuçları TTL ile önbelleğe almak
 Nerede Kullanılır: VideoSearchService içindeki yerel arama akışları.
*/


import Foundation

// Basit yerel arama: YouTube sonuç sayfasını çekip temel bilgiler çıkarılır
enum LocalSearchAdapter {
    static func search(query: String, hl: String? = nil, gl: String? = nil, bypassCache: Bool = false) async throws -> [YouTubeVideo] {
        // Bölgeye bağlı değişkenliği önlemek için aramayı her zaman en/US ile yap
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { throw URLError(.badURL) }
    let urlString = "https://www.youtube.com/results?search_query=\(encoded)&hl=en&persist_hl=1&gl=US&persist_gl=1"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        // Cache lookup (1 hour TTL) – allow bypass on explicit refresh
        let key = CacheKey("search|q=\(query.lowercased())|hl=en|gl=US")
        if !bypassCache {
            if let cached: [YouTubeVideo] = await GlobalCaches.json.get(key: key, type: [YouTubeVideo].self) {
                return cached
            }
        }

        var req = RequestFactory.makeYouTubeHTMLRequest(url: url, hl: "en", gl: "US")

        let (data, _) = try await URLSession.shared.data(for: req)
    guard let html = String(data: data, encoding: .utf8) else { throw URLError(.cannotDecodeContentData) }

        // initialData: ytInitialData aramasından basit bir JSON çıkarmaya çalışalım
    guard let jsonStr = ParsingUtils.extractJSON(from: html, startMarker: "ytInitialData = ", endMarker: "};") else {
            // Fallback: hiçbir şey bulunamazsa boş dön
            return []
        }
        let jsonData = Data((jsonStr + "}").utf8)
        let root = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        // Çok kapsamlı parse yerine, tipik path: contents.twoColumnSearchResultsRenderer.primaryContents.sectionListRenderer.contents[].itemSectionRenderer.contents[]
    var videos: [YouTubeVideo] = []
        if let contents = ((root?["contents"] as? [String: Any])?["twoColumnSearchResultsRenderer"] as? [String: Any])?["primaryContents"] as? [String: Any],
           let sectionList = contents["sectionListRenderer"] as? [String: Any],
           let sections = sectionList["contents"] as? [[String: Any]] {
            for section in sections {
                if let itemSection = section["itemSectionRenderer"] as? [String: Any],
                   let items = itemSection["contents"] as? [[String: Any]] {
                    for item in items {
                        if let videoRenderer = item["videoRenderer"] as? [String: Any],
                           let id = videoRenderer["videoId"] as? String,
                           let titleObj = videoRenderer["title"] as? [String: Any],
                           let runs = titleObj["runs"] as? [[String: Any]],
                           let title = runs.first?["text"] as? String {
                            let channelTitle = ((videoRenderer["ownerText"] as? [String: Any])?["runs"] as? [[String: Any]])?.first?["text"] as? String ?? ""
                            let channelId = ((videoRenderer["ownerText"] as? [String: Any])?["runs"] as? [[String: Any]])?.first?["navigationEndpoint"] as? [String: Any]
                            let channelBrowseId = ((channelId?["browseEndpoint"] as? [String: Any])?["browseId"] as? String) ?? ""
                            let publishedAtRaw = ((videoRenderer["publishedTimeText"] as? [String: Any])?["simpleText"] as? String) ?? ""
                            let description = ((videoRenderer["detailedMetadataSnippets"] as? [[String: Any]])?.first?["snippetText"] as? [String: Any])?["runs"] as? [[String: Any]]
                            let descText = description?.map { ($0["text"] as? String) ?? "" }.joined() ?? ""
                            let thumbArr = (videoRenderer["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]]
                            let thumb = thumbArr?.last?["url"] as? String ?? youtubeThumbnailURL(id, quality: .mqdefault)
                            let viewsTextRaw = ((videoRenderer["viewCountText"] as? [String: Any])?["simpleText"] as? String) ?? ""
                            var durationText = ""
                            if let lt = videoRenderer["lengthText"] as? [String: Any] {
                                if let s = lt["simpleText"] as? String { durationText = s }
                                else if let runs2 = lt["runs"] as? [[String: Any]], let t = runs2.first?["text"] as? String { durationText = t }
                            }
                            var durationSeconds: Int? = nil
                            if let lenStr = (videoRenderer["lengthSeconds"] as? String) ?? (videoRenderer["lengthSeconds"] as? NSNumber)?.stringValue { durationSeconds = Int(lenStr) }

                            // Use central normalization helpers to ensure consistency with all other flows
                            let normalizedViews: String = normalizeViewCountText(viewsTextRaw)
                            let (normalizedPublished, publishedISO) = normalizePublishedDisplay(publishedAtRaw)

                            let video = YouTubeVideo(
                                id: id,
                                title: title,
                                channelTitle: channelTitle,
                                channelId: channelBrowseId,
                                viewCount: normalizedViews,
                                publishedAt: normalizedPublished,
                                publishedAtISO: publishedISO,
                                thumbnailURL: thumb,
                                description: descText,
                                channelThumbnailURL: "",
                                likeCount: "0",
                                durationText: durationText,
                                durationSeconds: durationSeconds
                            )
                            videos.append(video)
                        }
                    }
                }
            }
        }
    // Still write results to cache so non-refresh calls benefit; bypass only skips read path
    await GlobalCaches.json.set(key: key, value: videos, ttl: CacheTTL.oneHour)
    return videos
    }
}
