/*
 File Overview (EN)
 Purpose: Facade extension for YouTubeAPIService that unifies view/service call sites while staying local-only.
 Key Responsibilities:
 - Route metadata fetches to Local adapters (scrape-based) and keep behavior stable
 - Provide normalization/enrichment helpers as a single source of truth
 - Avoid calling Official API modules from here by design
 Used By: Views and services that need a single entry for metadata/enrichment.

 Dosya Özeti (TR)
 Amacı: YouTubeAPIService için, görünüm/servis çağrılarını tek noktada birleştiren ancak yalnızca yerel adaptörleri kullanan cephe (facade) katmanı.
 Ana Sorumluluklar:
 - Meta veri çağrılarını Local adaptörlere yönlendirerek mevcut davranışı korumak
 - Normalizasyon ve zenginleştirme yardımcılarını tek kaynakta toplamak
 - Tasarım gereği buradan Resmi API modüllerine çağrı yapmamak
 Nerede Kullanılır: Meta veri/zenginleştirme için tek giriş noktasına ihtiyaç duyan view ve servisler.
*/

import Foundation

// IMPORTANT: LOCAL-ONLY FACADE
// ---------------------------------
// This extension is a unification layer for VIEW/SERVICE call sites, but it must
// call ONLY Local adapters/services (scrape-based) to preserve current behavior.
// DO NOT add Official API calls here. Any Official integrations (e.g., subscriber
// counts) must remain in their dedicated integration modules with caching logic.
// ---------------------------------
// Views should go through YouTubeAPIService instead of calling adapters directly.
extension YouTubeAPIService {
    /// Fetch lightweight video metadata by scraping the watch page (local, fast).
    /// Returns title, author (channel title), view count text, published time text, and optional duration.
    func fetchVideoMetadata(videoId: String, hl: String? = nil, gl: String? = nil) async throws -> LocalVideoData {
        let locale = hl != nil || gl != nil ? (hl: hl, gl: gl) : self.currentLocaleParams()
        return try await LocalYouTubeService.shared.fetchVideo(videoId: videoId, hl: locale.hl, gl: locale.gl)
    }

    /// Quickly retrieve channel info (title and thumbnail) using local adapter. Uses en/US for stability.
    func quickChannelInfo(channelId: String) async -> YouTubeChannel? {
        return try? await LocalChannelAdapter.fetchChannelInfo(channelId: channelId, hl: "en", gl: "US")
    }

    // MARK: - Central normalization helpers (single source of truth)
    /// Normalize any viewCount text into a consistent localized display using UtilityFunctions.
    /// Accepts raw strings like "1.2K", "123.456 görüntüleme", or placeholders. Returns a stable label.
    func normalizeViewCount(_ raw: String) -> String {
        return normalizeViewCountText(raw)
    }

    /// Normalize publishedAt display. If ISO provided use it; otherwise try relative -> ISO, then formatDate.
    /// Returns (displayText, isoStringOptional)
    func normalizePublishedAt(_ raw: String, iso: String? = nil) -> (String, String?) {
        return normalizePublishedDisplay(raw, iso: iso)
    }

    // MARK: - Shared enrichment helpers
    /// Meta verilerle belirli indekslerdeki videoları zenginleştirir.
    /// - Parameters:
    ///   - items: Kaynak video listesi
    ///   - indices: Zenginleştirilecek indeksler (listenin sınırları içinde olmalı)
    ///   - locale: (hl, gl) yerel ayarları; boş bırakılırsa currentLocaleParams() kullanın
    /// - Returns: (index, enrichedVideo) çifti listesi, sadece başarıyla zenginleşenler döner
    func enrichVideos(items: [YouTubeVideo], indices: [Int], locale: (hl: String, gl: String?)? = nil) async -> [(Int, YouTubeVideo)] {
        if indices.isEmpty { return [] }
        let loc = locale ?? self.currentLocaleParams()
        return await withTaskGroup(of: (Int, YouTubeVideo?).self, returning: [(Int, YouTubeVideo)].self) { group in
            for i in indices {
                guard i >= 0 && i < items.count else { continue }
                let base = items[i]
                let vid = base.id
                group.addTask { [loc] in
                    do {
                        let meta = try await self.fetchVideoMetadata(videoId: vid, hl: loc.hl, gl: loc.gl)
                        let (displayDate, isoGuess) = self.normalizePublishedAt(meta.publishedTimeText)
                        let displayViews = self.normalizeViewCount(meta.viewCountText)
                        let merged = YouTubeVideo(
                            id: base.id,
                            title: base.title.isEmpty ? meta.title : base.title,
                            channelTitle: base.channelTitle.isEmpty ? meta.author : base.channelTitle,
                            channelId: base.channelId.isEmpty ? (meta.channelId ?? "") : base.channelId,
                            viewCount: displayViews,
                            publishedAt: displayDate,
                            publishedAtISO: isoGuess,
                            thumbnailURL: base.thumbnailURL.isEmpty ? youtubeThumbnailURL(base.id, quality: .hqdefault) : base.thumbnailURL,
                            description: base.description.isEmpty ? meta.effectiveDescription : base.description,
                            channelThumbnailURL: base.channelThumbnailURL,
                            likeCount: base.likeCount,
                            durationText: base.durationText.isEmpty ? meta.durationText : base.durationText,
                            durationSeconds: base.durationSeconds ?? meta.durationSeconds
                        )
                        return (i, merged)
                    } catch {
                        return (i, nil)
                    }
                }
            }
            var out: [(Int, YouTubeVideo)] = []
            for await (idx, enriched) in group { if let v = enriched { out.append((idx, v)) } }
            return out
        }
    }

    /// Listenin başındaki ilk `maxCount` öğeyi hızlıca zenginleştirir.
    func enrichFirst(items: [YouTubeVideo], maxCount: Int, locale: (hl: String, gl: String?)? = nil) async -> [(Int, YouTubeVideo)] {
        let count = max(0, min(maxCount, items.count))
        if count == 0 { return [] }
        let indices = Array(0..<count)
        return await enrichVideos(items: items, indices: indices, locale: locale)
    }
}
