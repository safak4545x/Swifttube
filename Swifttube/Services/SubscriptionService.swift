/*
 File Overview (EN)
 Purpose: Build a local feed of subscription videos by fetching recent items from subscribed channels.
 Key Responsibilities:
 - Iterate userSubscriptionsFromURL and fetch recent videos with LocalChannelAdapter
 - De-dupe, shuffle, and enrich with channel thumbnails; normalize views/dates
 - Update YouTubeAPIService state flags and publish results to UI
 Used By: SubscriptionsView feed population.

 Dosya Özeti (TR)
 Amacı: Abone olunan kanallardan yerel olarak son videoları çekerek abonelik akışını oluşturmak.
 Ana Sorumluluklar:
 - userSubscriptionsFromURL üzerinden dolaşıp LocalChannelAdapter ile yeni videoları almak
 - Yinelenenleri temizlemek, karıştırmak ve kanal avatarı ile zenginleştirmek; görüntülenme/tarihi normalize etmek
 - YouTubeAPIService durum bayraklarını güncellemek ve sonuçları UI'a yayınlamak
 Nerede Kullanılır: SubscriptionsView akışını doldurmak.
*/


import Foundation

extension YouTubeAPIService {
    
    func fetchSubscriptionVideos(completion: @escaping ([YouTubeVideo]) -> Void = { _ in }) {
        print("🔔 LocalAPI: Fetch subscription videos from \(userSubscriptionsFromURL.count) channels")
        guard !userSubscriptionsFromURL.isEmpty else {
            DispatchQueue.main.async { self.subscriptionVideos = [] }
            completion([])
            return
        }
        isLoading = true
        Task { @MainActor in
            var merged: [YouTubeVideo] = []
            for channel in userSubscriptionsFromURL.prefix(15) { // limit work
                do {
                    var vids = try await LocalChannelAdapter.fetchChannelVideos(channelId: channel.id)
                    vids = Array(vids.prefix(6))
                    merged.append(contentsOf: vids)
                } catch {
                    print("⚠️ Local subs: failed channel \(channel.title): \(error)")
                }
            }
            var seen = Set<String>()
            merged = merged.filter { seen.insert($0.id).inserted }
            merged.shuffle()
            var channelThumbs: [String: String] = [:]
            for chId in Set(merged.map { $0.channelId }) {
                if let info = await self.quickChannelInfo(channelId: chId) {
                    channelThumbs[chId] = info.thumbnailURL
                }
            }
            let updated = merged.map { v -> YouTubeVideo in
                let thumb = channelThumbs[v.channelId] ?? v.channelThumbnailURL
                let fallbackTitle = self.userSubscriptionsFromURL.first(where: { $0.id == v.channelId })?.title ?? v.channelTitle
                let channelTitle = v.channelTitle.isEmpty ? fallbackTitle : v.channelTitle
                // Normalize via central helpers
                let normalizedViews: String = self.normalizeViewCount(v.viewCount)
                let (normalizedPublished, publishedISO) = self.normalizePublishedAt(v.publishedAt, iso: v.publishedAtISO)
                return YouTubeVideo(
                    id: v.id, title: v.title, channelTitle: channelTitle, channelId: v.channelId,
                    viewCount: normalizedViews,
                    publishedAt: normalizedPublished, publishedAtISO: publishedISO,
                    thumbnailURL: v.thumbnailURL, description: v.description,
                    channelThumbnailURL: thumb, likeCount: v.likeCount,
                    durationText: v.durationText, durationSeconds: v.durationSeconds)
            }
            self.subscriptionVideos = updated
            if !updated.isEmpty { self.fetchChannelThumbnails(for: updated, isSubscription: true) }
            self.isLoading = false
            completion(updated)
        }
    }
    
    // Son 7 günlük tarih formatı
    func getRecentDateISO() -> String {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: weekAgo)
    }

    // Removed local isoFromRelative wrapper; all callers use normalizePublishedAt
}
