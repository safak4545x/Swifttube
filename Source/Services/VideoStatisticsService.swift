
/*
 File Overview (EN)
 Purpose: Fetch and apply video statistics (e.g., like counts) using the official API when available; provide helpers to update video lists.
 Key Responsibilities:
 - Build videos.list requests (part=statistics) and parse responses
 - Update like/view counts across home, related, shorts, and subscriptions lists
 - Provide safe fallbacks for local-only mode (skip remote calls)
 Used By: YouTubeAPIService for enriching displayed video metadata.

 Dosya Özeti (TR)
 Amacı: Mümkün olduğunda resmi API ile video istatistiklerini (ör. beğeni) çekmek; video listelerini güncellemek için yardımcılar sağlamak.
 Ana Sorumluluklar:
 - videos.list (part=statistics) çağrıları yapıp yanıtları ayrıştırmak
 - Ana sayfa, ilgili, shorts ve abonelik listelerinde like/görüntülenme alanlarını güncellemek
 - Sadece yerel modda güvenli geri çekilmeler (uzak çağrıyı atla)
 Nerede Kullanılır: YouTubeAPIService, gösterilen video metadatasını zenginleştirmek için.
*/

import Foundation

extension YouTubeAPIService {
    
    // Tek video için detaylı bilgi çeken fonksiyon (like count dahil)
    func fetchVideoDetails(videoId: String) {
        let apiKey = self.apiKey
        guard !apiKey.isEmpty else { return }
        // Aynı anda tekrarını engelle
        if fetchingLikeFor.contains(videoId) { return }
        fetchingLikeFor.insert(videoId)
        Task {
            // Çıkışta ana threadda flag temizle
            defer {
                DispatchQueue.main.async { self.fetchingLikeFor.remove(videoId) }
            }
            var comps = URLComponents(string: "https://www.googleapis.com/youtube/v3/videos")!
            comps.queryItems = [
                .init(name: "part", value: "statistics"),
                .init(name: "id", value: videoId),
                .init(name: "key", value: apiKey)
            ]
            guard let url = comps.url else { return }
            do {
                let (data, resp) = try await URLSession.shared.data(from: url)
                if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                    return
                }
                guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let items = obj["items"] as? [[String: Any]], let first = items.first,
                      let stats = first["statistics"] as? [String: Any] else { return }
                let likeRaw = (stats["likeCount"] as? String) ?? "0"
                let formatted = formatCountShort(likeRaw)
                await MainActor.run {
                    self.likeCountByVideoId[videoId] = formatted
                }
            } catch {
                // Ağ hatası sessiz geçilir (yalnızca like yok kalır)
            }
        }
    }
    
    // Video listelerinde belirli bir videoyu güncelleme fonksiyonu
    private func updateVideoInLists(videoId: String, likeCount: String, viewCount: String) {
    let formattedLikeCount = formatCountShort(likeCount)
    let formattedViewCount = normalizeViewCountText(viewCount)
        
        // Normal videolarda ara ve güncelle
        if let index = videos.firstIndex(where: { $0.id == videoId }) {
            let video = videos[index]
            videos[index] = YouTubeVideo(
                id: video.id,
                title: video.title,
                channelTitle: video.channelTitle,
                channelId: video.channelId,
                viewCount: formattedViewCount,
                publishedAt: video.publishedAt,
                thumbnailURL: video.thumbnailURL,
                description: video.description,
                channelThumbnailURL: video.channelThumbnailURL,
                likeCount: formattedLikeCount,
                durationText: video.durationText,
                durationSeconds: video.durationSeconds
            )
        }
        
        // Related videolarda ara ve güncelle
        if let index = relatedVideos.firstIndex(where: { $0.id == videoId }) {
            let video = relatedVideos[index]
            relatedVideos[index] = YouTubeVideo(
                id: video.id,
                title: video.title,
                channelTitle: video.channelTitle,
                channelId: video.channelId,
                viewCount: formattedViewCount,
                publishedAt: video.publishedAt,
                thumbnailURL: video.thumbnailURL,
                description: video.description,
                channelThumbnailURL: video.channelThumbnailURL,
                likeCount: formattedLikeCount,
                durationText: video.durationText,
                durationSeconds: video.durationSeconds
            )
        }
        
        // Shorts videolarda ara ve güncelle
        if let index = shortsVideos.firstIndex(where: { $0.id == videoId }) {
            let video = shortsVideos[index]
            shortsVideos[index] = YouTubeVideo(
                id: video.id,
                title: video.title,
                channelTitle: video.channelTitle,
                channelId: video.channelId,
                viewCount: formattedViewCount,
                publishedAt: video.publishedAt,
                thumbnailURL: video.thumbnailURL,
                description: video.description,
                channelThumbnailURL: video.channelThumbnailURL,
                likeCount: formattedLikeCount,
                durationText: video.durationText,
                durationSeconds: video.durationSeconds
            )
        }
        
        // Subscription videolarda ara ve güncelle
        if let index = subscriptionVideos.firstIndex(where: { $0.id == videoId }) {
            let video = subscriptionVideos[index]
            subscriptionVideos[index] = YouTubeVideo(
                id: video.id,
                title: video.title,
                channelTitle: video.channelTitle,
                channelId: video.channelId,
                viewCount: formattedViewCount,
                publishedAt: video.publishedAt,
                thumbnailURL: video.thumbnailURL,
                description: video.description,
                channelThumbnailURL: video.channelThumbnailURL,
                likeCount: formattedLikeCount,
                durationText: video.durationText,
                durationSeconds: video.durationSeconds
            )
        }
    }
    
    func fetchVideoStatistics(
        videoIds: [String], completion: @escaping ([YouTubeVideo]) -> Void
    ) {
    // Local-only: istatistik çekme devre dışı, doğrudan mevcut relatedVideos döndürülür
    // fetchVideoStatistics skipped (local-only)
    completion(self.relatedVideos)
    }

    private func parseVideo(from item: [String: Any]) -> YouTubeVideo? {
        guard let id = item["id"] as? String,
            let snippet = item["snippet"] as? [String: Any],
            let statistics = item["statistics"] as? [String: Any],
            let title = snippet["title"] as? String,
            let channelTitle = snippet["channelTitle"] as? String,
            let channelId = snippet["channelId"] as? String,
            let publishedAt = snippet["publishedAt"] as? String,
            let description = snippet["description"] as? String,
            let thumbnails = snippet["thumbnails"] as? [String: Any],
            let medium = thumbnails["medium"] as? [String: Any],
            let thumbnailURL = medium["url"] as? String,
            let viewCountString = statistics["viewCount"] as? String
        else {
            return nil
        }
        
        let likeCountString = statistics["likeCount"] as? String ?? "0"

        let (publishedDisplay, publishedISO) = normalizePublishedDisplay(publishedAt)
        return YouTubeVideo(
            id: id,
            title: title,
            channelTitle: channelTitle,
            channelId: channelId,
            viewCount: normalizeViewCountText(viewCountString),
            publishedAt: publishedDisplay,
            publishedAtISO: publishedISO,
            thumbnailURL: thumbnailURL,
            description: description,
            channelThumbnailURL: "",
            likeCount: formatCountShort(likeCountString),
            durationText: "",
            durationSeconds: nil
        )
    }
    
    // Kanal profil fotoğraflarını ve video istatistiklerini çeken fonksiyon
    internal func fetchChannelThumbnails(for videos: [YouTubeVideo], isShorts: Bool = false, isWatchHistory: Bool = false, isSubscription: Bool = false) {
        // Local mode only avatar enrichment
        Task {
            let uniqueIds = Array(Set(videos.map { $0.channelId })).filter { !$0.isEmpty }
            if uniqueIds.isEmpty { return }
            // Avatar enrichment start

            // Fetch off-main concurrently
            var channelThumbs: [String: String] = [:]
            var fetchedPairs: [(String, String?)] = []
            await withTaskGroup(of: (String, String?).self) { group in
                for chId in uniqueIds {
                    group.addTask {
                        let info: YouTubeChannel? = await self.quickChannelInfo(channelId: chId)
                        return (chId, info?.thumbnailURL)
                    }
                }
                for await pair in group { fetchedPairs.append(pair) }
            }
            for (chId, urlOpt) in fetchedPairs {
                if let url = urlOpt, !url.isEmpty {
                    channelThumbs[chId] = normalizeAvatarURL(url)
                } else {
                    // Avatar enrichment miss channel=\(chId)
                }
            }
            // Avatar enrichment finished (count: \(channelThumbs.count))

            // Snapshot to immutable to avoid Swift 6 concurrent capture warning
            let finalThumbs = channelThumbs

            await MainActor.run {
                func apply(to list: inout [YouTubeVideo]) {
                    guard !list.isEmpty else { return }
                    for i in 0..<list.count {
                        let v = list[i]
                        let thumb = finalThumbs[v.channelId] ?? v.channelThumbnailURL
                        list[i] = YouTubeVideo(
                            id: v.id,
                            title: v.title,
                            channelTitle: v.channelTitle,
                            channelId: v.channelId,
                            viewCount: v.viewCount,
                            publishedAt: v.publishedAt,
                            publishedAtISO: v.publishedAtISO,
                            thumbnailURL: v.thumbnailURL,
                            description: v.description,
                            channelThumbnailURL: thumb,
                            likeCount: v.likeCount,
                            durationText: v.durationText,
                            durationSeconds: v.durationSeconds
                        )
                    }
                }
                if isWatchHistory { apply(to: &self.watchHistory) }
                else if isShorts { apply(to: &self.shortsVideos) }
                else if isSubscription { apply(to: &self.subscriptionVideos) }
                else { apply(to: &self.videos) }
            }
        }
    }
}
