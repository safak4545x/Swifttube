/*
 File Overview (EN)
 Purpose: Channel-related operations using local scraping: search channels, fetch videos/info, and enrich missing fields.
 Key Responsibilities:
 - Use LocalChannelAdapter to search channels and list videos (en/US pinned for stability)
 - Normalize view counts/dates centrally; fill missing channel titles/avatars
 - Provide popular videos subset and update UI state flags
 Used By: Channel pages and search flows in the app.

 Dosya Özeti (TR)
 Amacı: Yerel kazımaya dayalı kanal işlemleri: kanal arama, video/info alma ve eksik alanları zenginleştirme.
 Ana Sorumluluklar:
 - LocalChannelAdapter ile kanalları aramak ve videoları listelemek (kararlılık için en/US sabit)
 - Görüntülenme/tarih alanlarını merkezî olarak normalize etmek; eksik kanal başlığı/avatarı doldurmak
 - Popüler videolar alt kümesini sağlamak ve UI durum bayraklarını güncellemek
 Nerede Kullanılır: Uygulamadaki kanal sayfaları ve arama akışları.
*/

import Foundation

extension YouTubeAPIService {
    
    func searchChannels(query: String) {
        guard !query.isEmpty else { return }
        isSearching = true
        Task { @MainActor in
            do {
                let result = try await LocalChannelAdapter.searchChannels(query: query)
                // Artık girişte subscriberCount'u zorla 0'a çekmiyoruz; adapter ne veriyorsa (şu an 0) bırakıyoruz.
                self.searchedChannels = result
                // Resmi API zenginleştirmesi (varsa) yine de çalışsın
                self.refreshSubscriberCounts(for: result.map { $0.id })
            } catch {
                self.error = "Kanallar aranırken hata oluştu"
            }
            self.isSearching = false
        }
    }
    
    func fetchChannelVideos(channelId: String) {
        Task { @MainActor in
            self.isLoading = true
            do {
                var vids = try await LocalChannelAdapter.fetchChannelVideos(channelId: channelId)
                // Eğer videolarda kanal başlığı veya thumb eksikse kanal bilgisini çek ve doldur
                if vids.contains(where: { $0.channelTitle.isEmpty || $0.channelThumbnailURL.isEmpty }) {
                    // Subscriber count and channel info are fetched with a fixed locale to avoid regional discrepancies
                    if let info = await self.quickChannelInfo(channelId: channelId) {
                        vids = vids.map { v in
                            if v.channelTitle.isEmpty || v.channelThumbnailURL.isEmpty {
                                return YouTubeVideo(
                                    id: v.id,
                                    title: v.title,
                                    channelTitle: v.channelTitle.isEmpty ? info.title : v.channelTitle,
                                    channelId: v.channelId,
                                    viewCount: v.viewCount,
                                    publishedAt: v.publishedAt,
                                    publishedAtISO: v.publishedAtISO,
                                    thumbnailURL: v.thumbnailURL,
                                    description: v.description,
                                    channelThumbnailURL: v.channelThumbnailURL.isEmpty ? info.thumbnailURL : v.channelThumbnailURL,
                                    likeCount: v.likeCount,
                                    durationText: v.durationText,
                                    durationSeconds: v.durationSeconds
                                )
                            }
                            return v
                        }
                    }
                }
                // Görüntülenme ve tarih için merkezî normalizasyonu uygula
                let normalized = vids.map { v -> YouTubeVideo in
                    let normalizedViews: String = self.normalizeViewCount(v.viewCount)
                    let (normalizedPublished, publishedISO) = self.normalizePublishedAt(v.publishedAt, iso: v.publishedAtISO)
                    return YouTubeVideo(
                        id: v.id,
                        title: v.title,
                        channelTitle: v.channelTitle,
                        channelId: v.channelId,
                        viewCount: normalizedViews,
                        publishedAt: normalizedPublished,
                        publishedAtISO: publishedISO,
                        thumbnailURL: v.thumbnailURL,
                        description: v.description,
                        channelThumbnailURL: v.channelThumbnailURL,
                        likeCount: v.likeCount,
                        durationText: v.durationText,
                        durationSeconds: v.durationSeconds
                    )
                }
                // Kanal videolarında da 1dk altı videoları normal listeden çıkar
                self.channelVideos = normalized.filter { !isUnderOneMinute($0) }
            } catch {
                self.channelVideos = []
                self.error = "Kanal videoları yüklenirken hata oluştu"
            }
            self.isLoading = false
        }
    }
    
    func fetchChannelInfo(channelId: String) {
        Task { @MainActor in
            self.isLoading = true
            // Always fetch with fixed locale for consistent subscriber counts
            if let info = await self.quickChannelInfo(channelId: channelId) {
                // Yerel adapter ne verdiyse doğrudan kullan; subscriberCount'u zorla sıfırlamıyoruz.
                self.channelInfo = info
                self.refreshSubscriberCounts(for: [channelId])
            } else {
                self.channelInfo = nil
            }
            self.isLoading = false
        }
    }
    
    func fetchChannelPopularVideos(channelId: String) {
        Task { @MainActor in
            do {
                var vids = try await LocalChannelAdapter.fetchChannelVideos(channelId: channelId)
                // Eğer videolarda kanal başlığı veya thumb eksikse kanal bilgisini çekip doldur
                if vids.contains(where: { $0.channelTitle.isEmpty || $0.channelThumbnailURL.isEmpty }) {
                    // Use fixed locale for channel info enrichment as well
                    if let info = await self.quickChannelInfo(channelId: channelId) {
                        vids = vids.map { v in
                            if v.channelTitle.isEmpty || v.channelThumbnailURL.isEmpty {
                                return YouTubeVideo(
                                    id: v.id,
                                    title: v.title,
                                    channelTitle: v.channelTitle.isEmpty ? info.title : v.channelTitle,
                                    channelId: v.channelId,
                                    viewCount: v.viewCount,
                                    publishedAt: v.publishedAt,
                                    publishedAtISO: v.publishedAtISO,
                                    thumbnailURL: v.thumbnailURL,
                                    description: v.description,
                                    channelThumbnailURL: v.channelThumbnailURL.isEmpty ? info.thumbnailURL : v.channelThumbnailURL,
                                    likeCount: v.likeCount,
                                    durationText: v.durationText,
                                    durationSeconds: v.durationSeconds
                                )
                            }
                            return v
                        }
                    }
                }
                // Görüntülenme ve tarih alanlarını anasayfa ile aynı biçimde normalize et (merkezî)
                let normalized = vids.map { v -> YouTubeVideo in
                    let normalizedViews: String = self.normalizeViewCount(v.viewCount)
                    let (normalizedPublished, publishedISO) = self.normalizePublishedAt(v.publishedAt, iso: v.publishedAtISO)
                    return YouTubeVideo(
                        id: v.id,
                        title: v.title,
                        channelTitle: v.channelTitle,
                        channelId: v.channelId,
                        viewCount: normalizedViews,
                        publishedAt: normalizedPublished,
                        publishedAtISO: publishedISO,
                        thumbnailURL: v.thumbnailURL,
                        description: v.description,
                        channelThumbnailURL: v.channelThumbnailURL,
                        likeCount: v.likeCount,
                        durationText: v.durationText,
                        durationSeconds: v.durationSeconds
                    )
                }
                // 1 dakikanın altındaki videoları (shorts) çıkar
                self.currentChannelPopularVideos = normalized.filter { !isUnderOneMinute($0) }
            } catch {
                print("⚠️ Channel popular videos fetch failed: \(error)")
                self.currentChannelPopularVideos = []
            }
        }
    }
}

// MARK: - Helpers
// Removed local isoFromRelative wrapper; central normalizePublishedAt covers it
