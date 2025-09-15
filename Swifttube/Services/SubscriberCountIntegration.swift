/*
 File Overview (EN)
 Purpose: Integrate official subscriber counts and playlist item counts with caching, and merge them into in-memory models.
 Key Responsibilities:
 - Debounce and batch requests to OfficialYouTubeSubscriberService (<=50 IDs)
 - Cache counts with TTL and hydrate UI immediately from cache when possible
 - Also fetch playlist item counts via OfficialYouTubePlaylistService and cache
 Used By: Channel pages, search results, subscriptions list, and playlist details.

 Dosya Özeti (TR)
 Amacı: Resmi abone sayıları ve oynatma listesi öğe sayılarının önbellekle entegrasyonunu yapıp bellek içi modellere uygulamak.
 Ana Sorumluluklar:
 - OfficialYouTubeSubscriberService’e istekleri (<=50 ID) toplu ve gecikmeli şekilde göndermek
 - Sayıları TTL ile önbelleğe almak ve mümkün olduğunda UI’ı anında cache’ten beslemek
 - OfficialYouTubePlaylistService ile oynatma listesi öğe sayısını çekip önbelleğe almak
 Nerede Kullanılır: Kanal sayfaları, arama sonuçları, abonelik listesi ve playlist detayları.
*/

import Foundation
import os.log

// MARK: - Official Subscriber Count Integration (Now With 8h Caching)
// Updated: Subscriber counts artık 8 saat (TTL) cache'leniyor (disk + memory) – sadece sayı listesi.
// Rules (rev):
//  - 8h TTL: Cache dolu ise API çağrısı yapılmadan değerler anında UI'a yansır.
//  - Eksik veya cache'te olmayan ID'ler için resmi API çağrısı (<=50) yapılır.
//  - Başarılı response -> cache'e yazılır (her kanal için ayrı key).
//  - Hata durumunda cache dokunulmaz; mevcut (varsa) eski değer korunur.
//  - Local adapter hala 0 verebilir; cache doldurunca UI güncellenecek.
extension YouTubeAPIService {

    // Internal logger
    private static let subscriberLog = Logger(subsystem: "Swifttube", category: "SubscriberCounts")

    /// Public entry to refresh subscriber counts for a set of channel IDs (duplicates removed).
    func refreshSubscriberCounts(for channelIds: [String]) {
        let unique = Set(channelIds.filter { !$0.isEmpty })
        guard !unique.isEmpty else { return }
        // 1) Immediate cache hydrate (main thread): apply any cached values before debounce scheduling
        Task { @MainActor in
            var cachedMap: [String: Int] = [:]
            for id in unique {
                if let cached: Int = await GlobalCaches.json.get(key: CacheKey("subcnt:chan:\(id)"), type: Int.self) {
                    cachedMap[id] = cached
                }
            }
            if !cachedMap.isEmpty { self.applySubscriberCountMap(cachedMap) }
        }
        // Debounce on main queue (UI + state consistency)
        DispatchQueue.main.async {
            self.pendingSubscriberRefreshIds.formUnion(unique)
            let delay: TimeInterval = 0.15
            self.subscriberRefreshDebounceWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let toProcess = self.pendingSubscriberRefreshIds
                self.pendingSubscriberRefreshIds.removeAll()
                guard !toProcess.isEmpty else { return }
                let chunks: [[String]] = stride(from: 0, to: toProcess.count, by: 50).map { Array(toProcess.dropFirst($0).prefix(50)) }
                for c in chunks { self.fetchSubscriberCountsChunk(c) }
            }
            self.subscriberRefreshDebounceWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    /// Fetch counts for one chunk and merge into in-memory models.
    private func fetchSubscriberCountsChunk(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        // Filter out IDs that we already have fresh cache values for (within TTL)
        Task { @MainActor in
            var uncached: [String] = []
            for id in ids {
                let key = CacheKey("subcnt:chan:\(id)")
                if let _: Int = await GlobalCaches.json.get(key: key, type: Int.self) {
                    // already fresh (was hydrated earlier or still valid) -> skip network
                    continue
                } else {
                    uncached.append(id)
                }
            }
            guard !uncached.isEmpty else { return }
            self.performSubscriberFetch(for: uncached)
        }
    }

    private func performSubscriberFetch(for ids: [String]) {
        let service = OfficialYouTubeSubscriberService { [weak self] in self?.apiKey }
        Task { [weak self] in
            guard let self else { return }
            await MainActor.run { self.fetchingSubscriberCountIds.formUnion(ids) }
            do {
                let map = try await service.fetchSubscriberCounts(for: ids)
                await MainActor.run {
                    self.applySubscriberCountMap(map)
                    self.fetchingSubscriberCountIds.subtract(ids)
                }
                // Persist to cache with 8h TTL
                for (id, val) in map {
                    Task { await GlobalCaches.json.set(key: CacheKey("subcnt:chan:\(id)"), value: val, ttl: CacheTTL.eightHours) }
                }
            } catch {
                await MainActor.run { self.fetchingSubscriberCountIds.subtract(ids) }
                switch error {
                case OfficialYouTubeSubscriberService.ServiceError.apiKeyMissing:
                    if !didLogMissingSubscriberAPIKey {
                        YouTubeAPIService.subscriberLog.error("Missing API key for subscriber counts. Provide key in Settings.")
                        didLogMissingSubscriberAPIKey = true
                    }
                case OfficialYouTubeSubscriberService.ServiceError.requestFailed:
                    if !didLogQuotaOrForbidden {
                        YouTubeAPIService.subscriberLog.error("Request failed for subscriber counts (possibly quota / forbidden). IDs: \(ids.joined(separator: ","))")
                        didLogQuotaOrForbidden = true
                    }
                default:
                    YouTubeAPIService.subscriberLog.debug("Subscriber fetch error: \(String(describing: error))")
                }
            }
        }
    }

    /// Merge fetched subscriber counts into current channel-related models.
    @MainActor
    private func applySubscriberCountMap(_ map: [String: Int]) {
        guard !map.isEmpty else { return }
        // Update detailed channel info if present
        if let info = channelInfo, let newVal = map[info.id], newVal != info.subscriberCount {
            channelInfo = YouTubeChannel(
                id: info.id,
                title: info.title,
                description: info.description,
                thumbnailURL: info.thumbnailURL,
                bannerURL: info.bannerURL,
                subscriberCount: newVal,
                videoCount: info.videoCount
            )
        }
        // Update searched channels
        if !searchedChannels.isEmpty {
            searchedChannels = searchedChannels.map { ch in
                guard let newVal = map[ch.id], newVal != ch.subscriberCount else { return ch }
                return YouTubeChannel(
                    id: ch.id,
                    title: ch.title,
                    description: ch.description,
                    thumbnailURL: ch.thumbnailURL,
                    bannerURL: ch.bannerURL,
                    subscriberCount: newVal,
                    videoCount: ch.videoCount
                )
            }
        }
        // Update user subscriptions
        if !userSubscriptionsFromURL.isEmpty {
            userSubscriptionsFromURL = userSubscriptionsFromURL.map { ch in
                guard let newVal = map[ch.id], newVal != ch.subscriberCount else { return ch }
                return YouTubeChannel(
                    id: ch.id,
                    title: ch.title,
                    description: ch.description,
                    thumbnailURL: ch.thumbnailURL,
                    bannerURL: ch.bannerURL,
                    subscriberCount: newVal,
                    videoCount: ch.videoCount
                )
            }
        }
    }
}

// MARK: - Playlist Item Count (Data API)
extension YouTubeAPIService {
    func queuePlaylistCountFetch(_ ids: [String]) {
        let unique = Set(ids.filter { !$0.isEmpty })
        if unique.isEmpty { return }
        // 1) Hydrate from cache immediately and collect missing IDs
        Task { @MainActor in
            var missing: Set<String> = []
            for id in unique {
                if let cached: Int = await GlobalCaches.json.get(key: CacheKey("plcnt:list:\(id)"), type: Int.self) {
                    // Use cached immediately; no skeleton for this id
                    self.totalPlaylistCountById[id] = cached
                    self.fetchingPlaylistCountIds.remove(id)
                } else {
                    // Not in cache – mark for fetch and show skeleton
                    self.totalPlaylistCountById[id] = nil
                    self.fetchingPlaylistCountIds.insert(id)
                    missing.insert(id)
                }
            }
            guard !missing.isEmpty else { return }
            // 2) Debounce network fetch only for missing IDs
            self.pendingPlaylistCountIds.formUnion(missing)
            self.playlistCountDebounceWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                let toProcess = self.pendingPlaylistCountIds
                self.pendingPlaylistCountIds.removeAll()
                let chunks = stride(from: 0, to: toProcess.count, by: 50).map { start -> [String] in
                    let arr = Array(toProcess)
                    let end = min(start + 50, arr.count)
                    return Array(arr[start..<end])
                }
                for c in chunks { self.fetchPlaylistCountsChunk(c) }
            }
            self.playlistCountDebounceWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }
    }

    private func fetchPlaylistCountsChunk(_ ids: [String]) {
        Task { [weak self] in
            guard let self = self else { return }
            let service = OfficialYouTubePlaylistService { [weak self] in self?.apiKey }
            do {
                let map = try await service.fetchItemCounts(for: ids)
                await MainActor.run {
                    for (pid, n) in map {
                        self.totalPlaylistCountById[pid] = n
                        // Persist to cache with 8h TTL
                        Task { await GlobalCaches.json.set(key: CacheKey("plcnt:list:\(pid)"), value: n, ttl: CacheTTL.eightHours) }
                    }
                    self.fetchingPlaylistCountIds.subtract(ids)
                }
            } catch OfficialYouTubePlaylistService.ServiceError.apiKeyMissing {
                if !self.didLogMissingSubscriberAPIKey {
                    self.didLogMissingSubscriberAPIKey = true
                    print("⚠️ YouTube API key missing for playlist counts")
                }
                await MainActor.run { self.fetchingPlaylistCountIds.subtract(ids) }
            } catch OfficialYouTubePlaylistService.ServiceError.requestFailed {
                print("⚠️ Playlist count request failed (network or quota)")
                await MainActor.run { self.fetchingPlaylistCountIds.subtract(ids) }
            } catch {
                print("⚠️ Playlist count unknown error: \(error)")
                await MainActor.run { self.fetchingPlaylistCountIds.subtract(ids) }
            }
        }
    }
}
