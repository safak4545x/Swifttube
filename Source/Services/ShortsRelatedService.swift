
/*
 File Overview (EN)
 Purpose: Build local Shorts feed and related videos using scraping adapters with locale-aware heuristics and caching.
 Key Responsibilities:
 - Generate localized seed queries; fetch and filter Shorts with language markers
 - Enrich missing metadata (views/dates) and channel avatars asynchronously
 - Manage tokens/locale guards, caching, and progressive UI updates
 Used By: Shorts tab and the related videos panel under a playing video.

 Dosya Özeti (TR)
 Amacı: Yerel adaptörlerle kazıma yaparak Shorts akışını ve ilgili videoları oluşturmak; dil duyarlı sezgiler ve önbellekleme kullanmak.
 Ana Sorumluluklar:
 - Yerelleştirilmiş tohum aramaları üretmek; dil işaretlerine göre Shorts sonuçlarını süzmek
 - Eksik metadataları (görüntülenme/tarih) ve kanal avatarlarını eşzamanlı olmayan şekilde zenginleştirmek
 - Token/bölge korumaları, önbellek ve kademeli UI güncellemelerini yönetmek
 Nerede Kullanılır: Shorts sekmesi ve oynatılan videonun altındaki ilgili videolar paneli.
*/

import Foundation

extension YouTubeAPIService {
    /// Localized, region-biased seed queries for Shorts, derived from localized trending terms + local shorts markers.
    /// This no longer depends on legacy VideoCategory; we use lightweight per-language trending terms.
    fileprivate func localizedShortsQueries() -> [String] {
        let loc = self.currentLocaleParams()
        let selectedCustom = self.selectedCustomCategoryId.flatMap { id in self.customCategories.first(where: { $0.id == id }) }
        return QueryBuilder.buildShortsSeedQueries(hl: loc.hl, gl: loc.gl, selectedCustom: selectedCustom)
    }

    /// Heuristic to detect Shorts markers in a title for the current language.
    fileprivate func isLikelyShortsTitle(_ title: String, hl: String) -> Bool {
        let t = title.lowercased()
        let keys = LanguageResources.shortsMarkers(for: hl)
        return keys.contains(where: { t.contains($0) })
    }
    func fetchShortsVideosIfNeeded() {
        if shortsVideos.isEmpty { fetchShortsVideos() }
    }

    func fetchShortsVideos(suppressOverlay: Bool = false, forceRefresh: Bool = false) {
        print("🎬 Local fetchShortsVideos")
        isLoadingShorts = true
        isLoading = isLoadingVideos || isLoadingShorts
        if !suppressOverlay { showGlobalLoading = true }
        let startLocale = self.currentLocaleParams()
        let token = UUID()
        self.shortsFetchToken = token
        Task { @MainActor in
            do {
                let queries = self.localizedShortsQueries()
                // Deterministic key for a given day to reuse cache
                let dayKey = ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: Date())).prefix(10)
                let locale = startLocale
                // Make cache also depend on selected custom category (or NONE)
                let catKey: String = {
                    if let sel = self.selectedCustomCategoryId, let custom = self.customCategories.first(where: { $0.id == sel }) {
                        // Use stable id + primary keyword to avoid collisions after edits
                        return "cat=\(custom.id.uuidString.prefix(8))|p=\(custom.primaryKeyword.lowercased())"
                    }
                    return "cat=NONE"
                }()
                let cacheKey = CacheKey("shorts:seed=\(dayKey)|hl=\(locale.hl)|gl=\(locale.gl ?? "GLOBAL")|\(catKey)")
                if !forceRefresh, let cached: [YouTubeVideo] = await GlobalCaches.json.get(key: cacheKey, type: [YouTubeVideo].self), !cached.isEmpty {
                    // Guard token/locale before applying cache
                    let current = self.currentLocaleParams()
                    guard self.shortsFetchToken == token, current.hl == startLocale.hl, current.gl == startLocale.gl else {
                        print("⏭️ Ignoring cached shorts (locale/token changed)")
                        return
                    }
                    self.shortsVideos = cached
                    self.isLoadingShorts = false
                    self.isLoading = self.isLoadingVideos || self.isLoadingShorts
                    self.showGlobalLoading = false
                    return
                }
                var all: [YouTubeVideo] = []
                // Use more queries when a custom category is active to better match intent
                let take = (self.selectedCustomCategoryId != nil) ? 3 : 2
                for q in queries.shuffled().prefix(take) {
                    let items = try await LocalSearchAdapter.search(query: q, hl: locale.hl, gl: locale.gl)
                    all.append(contentsOf: items)
                }
                // Prefer language-aware detection of shorts markers in titles
                var shorts = all.filter { v in self.isLikelyShortsTitle(v.title, hl: locale.hl) }
                // If a custom category is selected, keep only relevant by keywords (soft check in title/desc)
                if let sel = self.selectedCustomCategoryId, let custom = self.customCategories.first(where: { $0.id == sel }) {
                    let keys: [String] = [custom.primaryKeyword, custom.secondaryKeyword, custom.thirdKeyword, custom.fourthKeyword].compactMap { $0?.lowercased() }.filter { !$0.isEmpty }
                    if !keys.isEmpty {
                        shorts = shorts.filter { v in
                            let t = (v.title + " " + v.description).lowercased()
                            return keys.contains(where: { t.contains($0) })
                        }
                    }
                }
                // Apply only date filter (ignore duration) when a filter is set on selected category
                if let sel = self.selectedCustomCategoryId, let custom = self.customCategories.first(where: { $0.id == sel }), let cutoff = custom.dateFilter.cutoffDate {
                    shorts = shorts.compactMap { v in
                        if let d = v.publishedAtISODate, d >= cutoff { return v }
                        let (_, iso) = self.normalizePublishedAt(v.publishedAt, iso: v.publishedAtISO)
                        if let iso, let dd = ISO8601DateFormatter().date(from: iso), dd >= cutoff {
                            return YouTubeVideo(id: v.id, title: v.title, channelTitle: v.channelTitle, channelId: v.channelId, viewCount: v.viewCount, publishedAt: v.publishedAt, publishedAtISO: iso, thumbnailURL: v.thumbnailURL, description: v.description, channelThumbnailURL: v.channelThumbnailURL, likeCount: v.likeCount, durationText: v.durationText, durationSeconds: v.durationSeconds)
                        }
                        return nil
                    }
                }
                var seen = Set<String>()
                shorts = shorts.filter { seen.insert($0.id).inserted }
                shorts.shuffle()
                shorts = Array(shorts.prefix(20))
                // İlk etapta hızlı gösterim: kanal avatarları olmadan listeyi bastır.
                // Guard token/locale before applying network results
                let current = self.currentLocaleParams()
                guard self.shortsFetchToken == token, current.hl == startLocale.hl, current.gl == startLocale.gl else {
                    print("⏭️ Ignoring stale shorts results (locale/token changed)")
                    return
                }
                self.shortsVideos = shorts
                // Cache shorts list for 30 minutes
                await GlobalCaches.json.set(key: cacheKey, value: shorts, ttl: CacheTTL.thirtyMinutes)
                // Loading overlay'i artık kapat (video oynatılabilir hale gelsin)
                self.isLoadingShorts = false
                self.isLoading = self.isLoadingVideos || self.isLoadingShorts
                self.showGlobalLoading = false
                // Kanal avatarlarını engelleyici olmayan arka plan görevinde (eşzamanlı) getir.
                let channelIds = Array(Set(shorts.map { $0.channelId }))
                Task {
                    // Paralel getirme
                    var channelThumbs: [String: String] = [:]
                    await withTaskGroup(of: (String, String?).self) { group in
                        for chId in channelIds {
                            group.addTask {
                                // Bölgeye göre kanal bilgisi
                                let info = await self.quickChannelInfo(channelId: chId)
                                return (chId, info?.thumbnailURL.isEmpty == false ? info?.thumbnailURL : nil)
                            }
                        }
                        for await (chId, thumb) in group { if let t = thumb { channelThumbs[chId] = t } }
                    }
                    if !channelThumbs.isEmpty {
                        // Ensure we're still on the same locale/token before applying post-enrichment updates
                        let current = self.currentLocaleParams()
                        guard self.shortsFetchToken == token, current.hl == startLocale.hl, current.gl == startLocale.gl else {
                            print("⏭️ Ignoring shorts avatar enrichment (locale/token changed)")
                            return
                        }
                        await MainActor.run {
                            // Yeniden eşle (kullanıcı bu sırada ayrılmış olabilir; index sınırlarına dikkat gerekmiyor çünkü map yeni kopya döndürüyor)
                            self.shortsVideos = self.shortsVideos.map { v in
                                let thumb = channelThumbs[v.channelId] ?? v.channelThumbnailURL
                                return YouTubeVideo(id: v.id, title: v.title, channelTitle: v.channelTitle, channelId: v.channelId, viewCount: v.viewCount, publishedAt: v.publishedAt, publishedAtISO: v.publishedAtISO, thumbnailURL: v.thumbnailURL, description: v.description, channelThumbnailURL: thumb, likeCount: v.likeCount)
                                // duration fields preserved
                            }
                        }
                    }
                }
                // Önceden kapattığımız için burada erken return.
                return
            } catch {
                print("⚠️ Local shorts fetch failed: \(error)")
                self.shortsVideos = []
            }
            self.isLoadingShorts = false
            self.isLoading = self.isLoadingVideos || self.isLoadingShorts
            self.showGlobalLoading = false
        }
    }
    
    func fetchRelatedVideos(videoId: String, channelId: String, videoTitle: String? = nil) {
        // Önce eski listeyi temizleyip spinner'ı göster
        Task { @MainActor in
            self.relatedVideos = []
            self.isLoadingRelated = true
        }

        // Ağ + parsing + zenginleştirme işlemlerini MainActor dışında yap (UI'yi bloklama)
        Task {
            do {
            let loc = self.currentLocaleParams()
            let items = try await LocalRelatedAdapter.fetchRelated(videoId: videoId, hl: loc.hl, gl: loc.gl)
                var trimmed = Array(items.prefix(20))
                // Eksik alanları belirle
                // Boşluk içeren (trim sonrası) viewCount / publishedAt alanları da eksik say
                let needsEnrichmentFlags = trimmed.map { v in
                    let vcEmpty = v.viewCount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    let dateEmpty = v.publishedAt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    return v.title == v.id || v.title.isEmpty || v.channelTitle.isEmpty || vcEmpty || dateEmpty
                }
                var ready: [YouTubeVideo] = []
                var needEnrichmentIndices: [Int] = []
                for (i, v) in trimmed.enumerated() {
                    if needsEnrichmentFlags[i] { needEnrichmentIndices.append(i) } else { ready.append(v) }
                }

                // İlk 8 videonun viewCount / publishedAt kesin gelsin diye onları da enrichment kuyruğuna ekle (zaten varsa tekrar eklenmez)
                let forceFirstCount = min(8, trimmed.count)
                if forceFirstCount > 0 {
                    var set = Set(needEnrichmentIndices)
                    for idx in 0..<forceFirstCount where !set.contains(idx) {
                        needEnrichmentIndices.append(idx)
                        set.insert(idx)
                    }
                }

                if !ready.isEmpty {
                    // Yalnızca tam verisi olanları hemen göster (placeholder başlık yok)
                    let readySnapshot = ready
                    let needEnrichmentEmpty = needEnrichmentIndices.isEmpty
                    await MainActor.run {
                        self.relatedVideos = readySnapshot
                        self.isLoadingRelated = needEnrichmentEmpty // Eğer hepsi hazırsa spinner kapanır
                    }
                }

                // Eğer tümü eksikse spinner açık kalsın ve önce hepsini zenginleştir.
                if ready.isEmpty { print("ℹ️ All related items need enrichment; delaying initial display") }

                if !needEnrichmentIndices.isEmpty {
                    print("🛠️ Related enrichment (parallel, count=\(needEnrichmentIndices.count)) starting… (forced first \(min(8, trimmed.count)))")
                    try await withThrowingTaskGroup(of: (Int, YouTubeVideo?).self) { group in
                        for idx in needEnrichmentIndices {
                            let v = trimmed[idx]
                            group.addTask {
                                do {
                                    let meta = try await self.fetchVideoMetadata(videoId: v.id, hl: loc.hl, gl: loc.gl)
                                    // viewCount & publishedAt: meta değerleri boş değilse her zaman tercih et (daha düzgün format)
                                    let newView = meta.viewCountText.trimmingCharacters(in: .whitespacesAndNewlines)
                                    let newDate = meta.publishedTimeText.trimmingCharacters(in: .whitespacesAndNewlines)
                                    // Normalize newly fetched view/date via central helpers
                                    let newViewDisplay = self.normalizeViewCount(newView.isEmpty ? v.viewCount : newView)
                                    let (newDateDisplay, newDateISO) = self.normalizePublishedAt(newDate.isEmpty ? v.publishedAt : newDate, iso: v.publishedAtISO ?? meta.publishedTimeText)
                                    let updated = YouTubeVideo(
                                        id: v.id,
                                        title: meta.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? v.title : meta.title,
                                        channelTitle: meta.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? v.channelTitle : meta.author,
                                        channelId: meta.channelId ?? v.channelId,
                                        viewCount: newViewDisplay,
                                        publishedAt: newDateDisplay,
                                        publishedAtISO: newDateISO,
                                        thumbnailURL: v.thumbnailURL,
                                        description: meta.shortDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? v.description : meta.shortDescription,
                                        channelThumbnailURL: v.channelThumbnailURL,
                                        likeCount: v.likeCount,
                                        durationText: v.durationText,
                                        durationSeconds: v.durationSeconds
                                    )
                                    #if DEBUG
                                    if v.viewCount != updated.viewCount || v.publishedAt != updated.publishedAt {
                                        print("✅ Enriched meta for id=\(v.id) views=\(updated.viewCount) date=\(updated.publishedAt)")
                                    }
                                    #endif
                                    return (idx, updated)
                                } catch {
                                    print("⚠️ Enrichment failed for id=\(v.id): \(error)")
                                    return (idx, nil)
                                }
                            }
                        }
                        for try await (idx, updated) in group { if let up = updated { trimmed[idx] = up } }
                    }
                }

                // Kanal avatarları (eksik) – tüm liste üzerinde (zaman önemli değil çünkü başlıklar artık hazır)
                let missingChannelIdsFinal = Set(trimmed.filter { $0.channelThumbnailURL.isEmpty && !$0.channelId.isEmpty }.map { $0.channelId })
                if !missingChannelIdsFinal.isEmpty {
                    var thumbs: [String: String] = [:]
                    await withTaskGroup(of: (String, String?).self) { group in
                        for chId in missingChannelIdsFinal {
                            group.addTask {
                                let info = await self.quickChannelInfo(channelId: chId)
                                return (chId, info?.thumbnailURL)
                            }
                        }
                        for await (chId, thumb) in group { if let t = thumb, !t.isEmpty { thumbs[chId] = t } }
                    }
                    if !thumbs.isEmpty {
                        for (i, v) in trimmed.enumerated() {
                            if let t = thumbs[v.channelId] { trimmed[i] = YouTubeVideo(id: v.id, title: v.title, channelTitle: v.channelTitle, channelId: v.channelId, viewCount: v.viewCount, publishedAt: v.publishedAt, publishedAtISO: v.publishedAtISO, thumbnailURL: v.thumbnailURL, description: v.description, channelThumbnailURL: t, likeCount: v.likeCount, durationText: v.durationText, durationSeconds: v.durationSeconds) }
                        }
                    }
                }

                // Nihai birleşik liste: enrichment sonrası (sıra korunuyor)
                let finalList = trimmed.filter { !($0.title == $0.id || $0.title.isEmpty) }
                let missingImmediately = finalList.filter { $0.viewCount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.publishedAt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                if !missingImmediately.isEmpty {
                    print("ℹ️ After primary enrichment, still missing meta count=\(missingImmediately.count)")
                } else {
                    print("✅ After primary enrichment, all related videos have basic meta")
                }
                // Tam listeyi tek seferde replace et (hazır + zenginleşenler karışık eski sürümleri tutma)
                await MainActor.run {
                    self.relatedVideos = finalList
                    self.isLoadingRelated = false
                }

                // Ek garanti: İlk 8 (veya daha az) videonun viewCount / publishedAt alanlarını mutlak güncelle.
                // (Önceki enrichment bunu yapmış olmalı ama yine de boş kalıyorsa burada zorla güncelliyoruz.)
                let guaranteeCount = min(8, finalList.count)
                if guaranteeCount > 0 {
                    let slice = Array(finalList.prefix(guaranteeCount))
                    Task.detached { [weak self] in
                        guard let self else { return }
                        var enriched: [String: YouTubeVideo] = [:]
                        await withTaskGroup(of: YouTubeVideo?.self) { group in
                            for v in slice {
                                group.addTask {
                                    if let meta = try? await self.fetchVideoMetadata(videoId: v.id, hl: loc.hl, gl: loc.gl) {
                                        let newView = meta.viewCountText.trimmingCharacters(in: .whitespacesAndNewlines)
                                        let newDate = meta.publishedTimeText.trimmingCharacters(in: .whitespacesAndNewlines)
                                        if !newView.isEmpty || !newDate.isEmpty {
                                            let newViewDisplay = self.normalizeViewCount(newView.isEmpty ? v.viewCount : newView)
                                            let (newDateDisplay, newDateISO) = self.normalizePublishedAt(newDate.isEmpty ? v.publishedAt : newDate, iso: v.publishedAtISO ?? meta.publishedTimeText)
                                            return YouTubeVideo(
                                                id: v.id,
                                                title: v.title,
                                                channelTitle: v.channelTitle.isEmpty ? meta.author : v.channelTitle,
                                                channelId: v.channelId.isEmpty ? (meta.channelId ?? v.channelId) : v.channelId,
                                                viewCount: newViewDisplay,
                                                publishedAt: newDateDisplay,
                                                publishedAtISO: newDateISO,
                                                thumbnailURL: v.thumbnailURL,
                                                description: v.description,
                                                channelThumbnailURL: v.channelThumbnailURL,
                                                likeCount: v.likeCount,
                                                durationText: v.durationText,
                                                durationSeconds: v.durationSeconds
                                            )
                                        }
                                    }
                                    return nil
                                }
                            }
                            for await maybe in group { if let v = maybe { enriched[v.id] = v } }
                        }
                        if enriched.isEmpty { return }
                        let enrichedCopy = enriched
                        await MainActor.run {
                            self.relatedVideos = self.relatedVideos.map { enrichedCopy[$0.id] ?? $0 }
                        }
                    }
                }

                // 5) Artçı metadata tamamlama (hala viewCount veya publishedAt boş kalanlar)
                let stillMissing = finalList.enumerated().compactMap { (idx, v) -> (Int, YouTubeVideo)? in
                    let vcEmpty = v.viewCount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    let pubEmpty = v.publishedAt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    return (vcEmpty || pubEmpty) ? (idx, v) : nil
                }
                if !stillMissing.isEmpty {
                    Task.detached { [weak self] in
                        guard let self else { return }
                        var updates: [(Int, YouTubeVideo)] = []
                        for (idx, v) in stillMissing {
                            if let meta = try? await self.fetchVideoMetadata(videoId: v.id, hl: loc.hl, gl: loc.gl) {
                                let newView = meta.viewCountText.trimmingCharacters(in: .whitespacesAndNewlines)
                                let newDate = meta.publishedTimeText.trimmingCharacters(in: .whitespacesAndNewlines)
                                let updated = YouTubeVideo(
                                    id: v.id,
                                    title: v.title,
                                    channelTitle: v.channelTitle.isEmpty ? meta.author : v.channelTitle,
                                    channelId: v.channelId.isEmpty ? (meta.channelId ?? v.channelId) : v.channelId,
                                    viewCount: newView.isEmpty ? v.viewCount : newView,
                                    publishedAt: newDate.isEmpty ? v.publishedAt : newDate,
                                    publishedAtISO: v.publishedAtISO ?? meta.publishedTimeText,
                                    thumbnailURL: v.thumbnailURL,
                                    description: v.description,
                                    channelThumbnailURL: v.channelThumbnailURL,
                                    likeCount: v.likeCount,
                                    durationText: v.durationText,
                                    durationSeconds: v.durationSeconds
                                )
                                updates.append((idx, updated))
                            }
                        }
                        if updates.isEmpty { return }
                        let updatesCopy = updates // snapshot to avoid Swift 6 warning
                        await MainActor.run {
                            // Eşleşen id'lere göre güncelle (index kaymış olabilir; id ile ararız)
                            var mapById: [String: YouTubeVideo] = [:]
                            for (_, u) in updatesCopy { mapById[u.id] = u }
                            self.relatedVideos = self.relatedVideos.map { mapById[$0.id] ?? $0 }
                        }
                    }
                }

                // Toplu fallback: viewCount / publishedAt hala eksik olan varsa hepsini paralel tek batch'te çek (normal ana sayfa istatistik yaklaşımı).
                Task.detached { [weak self] in
                    guard let self else { return }
                    let missingIds = await MainActor.run { self.relatedVideos.filter { $0.viewCount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.publishedAt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map { $0.id } }
                    if missingIds.isEmpty { return }
                    var enriched: [String: (String, String, String?)] = [:] // id -> (viewCount, publishedAt, iso)
                    await withTaskGroup(of: (String, String, String)?.self) { group in
                        for vid in missingIds {
                            group.addTask {
                                if let meta = try? await self.fetchVideoMetadata(videoId: vid, hl: loc.hl, gl: loc.gl) {
                                    let vc = meta.viewCountText.trimmingCharacters(in: .whitespacesAndNewlines)
                                    let date = meta.publishedTimeText.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !vc.isEmpty || !date.isEmpty { return (vid, vc, date) }
                                }
                                return nil
                            }
                        }
                        for await result in group { if let (vid, vc, date) = result { enriched[vid] = (vc, date, nil) } }
                    }
                    if enriched.isEmpty { return }
                    let enrichedSnapshot = enriched
                    await MainActor.run {
                        self.relatedVideos = self.relatedVideos.map { v in
                            if let tup = enrichedSnapshot[v.id] {
                                let (vc, date, _) = tup
                                let newViewDisplay = self.normalizeViewCount(vc.isEmpty ? v.viewCount : vc)
                                let (newDateDisplay, newDateISO) = self.normalizePublishedAt(date.isEmpty ? v.publishedAt : date, iso: v.publishedAtISO)
                                return YouTubeVideo(id: v.id, title: v.title, channelTitle: v.channelTitle, channelId: v.channelId, viewCount: newViewDisplay, publishedAt: newDateDisplay, publishedAtISO: newDateISO, thumbnailURL: v.thumbnailURL, description: v.description, channelThumbnailURL: v.channelThumbnailURL, likeCount: v.likeCount, durationText: v.durationText, durationSeconds: v.durationSeconds)
                            }
                            return v
                        }
                        let remaining = self.relatedVideos.filter { $0.viewCount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.publishedAt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
                        print("🔁 Batch fallback updated \(enrichedSnapshot.count) items. Remaining missing meta=\(remaining)")
                    }
                }
            } catch {
                print("⚠️ Local related parse failed: \(error)")
                await MainActor.run {
                    self.relatedVideos = []
                    self.isLoadingRelated = false
                }
            }
        }
    }
}
