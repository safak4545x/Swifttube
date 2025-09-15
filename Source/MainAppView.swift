/*
 File Overview (EN)
 Purpose: Hosts the app's root SwiftUI view (MainAppView) and defines YouTubeAPIService, the central observable model orchestrating data fetching, caching, region handling, playlists, and UI-related states.
 Key Responsibilities (YouTubeAPIService):
 - Manage videos, shorts, subscriptions, search, comments, related, and live viewers data
 - Coordinate region selection (hl/gl cookies), caches, and initial home load
 - Provide playlist helpers (local + remote) and user playlist persistence
 - Expose utility finders and normalization helpers for UI
 Key Responsibilities (MainAppView):
 - Simple wrapper that presents MainContentView as the app's root content
 Used By: SwifttubeApp injects this into WindowGroup.

 Dosya Özeti (TR)
 Amacı: Uygulamanın kök SwiftUI görünümünü (MainAppView) barındırır ve veri orkestrasyonunun merkezi olan YouTubeAPIService'i tanımlar; veri çekme, önbellek, bölge yönetimi ve playlist işlevlerini sağlar.
 Ana Sorumluluklar (YouTubeAPIService):
 - Videolar, shorts, abonelikler, arama, yorumlar, ilgili içerik ve canlı izleyiciler verisini yönetmek
 - Bölge seçimi (hl/gl çerezleri), cache'ler ve tek seferlik başlangıç yüklemesini koordine etmek
 - Playlist yardımcıları (yerel + uzak) ve kullanıcı playlist kalıcılığı sağlamak
 - UI için bulucu ve normalizasyon yardımcılarını sunmak
 Ana Sorumluluklar (MainAppView):
 - Uygulamanın kök içeriği olarak MainContentView'i sunan basit bir sarmalayıcı
 Nerede Kullanılır: SwifttubeApp, WindowGroup içinde bunu kullanır.
*/

import Foundation
import SwiftUI
import NaturalLanguage

// YouTube API Service
class YouTubeAPIService: ObservableObject {
    @Published var videos: [YouTubeVideo] = []
    @Published var shortsVideos: [YouTubeVideo] = []
    @Published var subscriptionVideos: [YouTubeVideo] = [] // Abone videolarını ayrı tut
    // Eski birleşik loading bayrağı (hala bazı görünümler kullanıyor). Artık alt bayrakların OR'u.
    @Published var isLoading: Bool = false
    @Published var isLoadingVideos: Bool = false
    @Published var isLoadingShorts: Bool = false
    // Global tam ekran loading overlay için ayrı bayrak (isLoading buton spinnerları için de kullanılıyor)
    @Published var showGlobalLoading = false
    @Published var error: String?
    @Published var channelInfo: YouTubeChannel? = nil
    @Published var comments: [YouTubeComment] = []
    @Published var relatedVideos: [YouTubeVideo] = []
    @Published var isLoadingRelated: Bool = false
    @Published var nextCommentsPageToken: String? = nil
    // Comments context: which videoId comments belong to (for local replies fetching)
    @Published var currentCommentsVideoId: String? = nil
    // Kanal popüler videoları (video detail ile çakışmaması için ayrı state)
    @Published var currentChannelPopularVideos: [YouTubeVideo] = []
    
    // Like sayıları için canlı sözlük
    @Published var likeCountByVideoId: [String: String] = [:]
    // Eski scraping iş akışından kalan ancak şu an minimal kullanım: tekrar tetiklemeyi engellemek için
    var fetchingLikeFor: Set<String> = []

    // Canlı izleyici sayıları (on-demand watch sayfasından çekilir)
    @Published var liveViewersByVideoId: [String: String] = [:]
    private var fetchingLiveViewers: Set<String> = []
    
    // Channel ve Playlist arama için yeni properties
    @Published var searchedChannels: [YouTubeChannel] = []
    @Published var searchedPlaylists: [YouTubePlaylist] = []
    @Published var channelVideos: [YouTubeVideo] = []
    @Published var playlistVideos: [YouTubeVideo] = []
    // Yerel playlist içerik cache'i: playlistId -> [YouTubeVideo]
    @Published var cachedPlaylistVideos: [String: [YouTubeVideo]] = [:]
    // Playlist toplam öğe sayısı (remote count veya local videoIds.count)
    @Published var totalPlaylistCountById: [String: Int] = [:]
    // In-flight playlist count fetches (for skeleton UI)
    @Published var fetchingPlaylistCountIds: Set<String> = []
    // User imported playlists (CSV)
    @Published var userPlaylists: [YouTubePlaylist] = [] {
        didSet { saveUserPlaylistsToUserDefaults() }
    }
    @Published var isSearching = false

    // Startup/async orchestration
    @Published private(set) var didPerformInitialHomeLoad = false
    @Published private(set) var didResolveRegion = false
    var categoryFetchToken: UUID? = nil
    var shortsFetchToken: UUID? = nil
    // One-time retry guard for initial empty home fetch
    private var didRetryEmptyHome = false
    // Region init + initial-load coordination
    private var isInitializingRegion: Bool = true
    private var pendingInitialHomeLoad: Bool = false

    // MARK: - Region selection (Algorithm > Location)
    @Published var selectedRegion: String = "GLOBAL" {
        didSet {
            // Avoid redundant work when assigning the same region value
            if oldValue == selectedRegion { return }
            // During app startup while resolving region, skip heavy refresh to avoid double fetches.
            if isInitializingRegion {
                Task {
                    await persistSelectedRegion()
                    let (hl, gl) = self.currentLocaleParams()
                    await resetYouTubeCookies(hl: hl, gl: gl)
                }
                NotificationCenter.default.post(name: .selectedRegionChanged, object: selectedRegion)
                return
            }
            // Reset in-memory lists immediately so UI reflects refresh state
            videos.removeAll()
            shortsVideos.removeAll()
            relatedVideos.removeAll()
            // Clear data caches so region-specific content doesn't reuse stale entries
            Task {
                // Preserve user preferences (custom categories) while clearing caches
                let preservedCategories = self.customCategories
                await GlobalCaches.json.clear()
                await GlobalCaches.images.clear()
                await persistSelectedRegion()
                URLCache.shared.removeAllCachedResponses()
                let (hl, gl) = self.currentLocaleParams()
                await resetYouTubeCookies(hl: hl, gl: gl)
                // Restore preserved preferences so custom categories remain after location change
                await GlobalCaches.json.set(key: self.customCategoriesCacheKey(), value: preservedCategories, ttl: CacheTTL.sevenDays * 52)
                await MainActor.run {
                    // Region change: refresh Home or selected custom category, and refresh Shorts
                          if let sel = self.selectedCustomCategoryId,
                              let custom = self.customCategories.first(where: { $0.id == sel }) {
                                self.fetchVideos(for: custom, suppressOverlay: true)
                    } else {
                        self.fetchHomeRecommendations(suppressOverlay: true)
                    }
                    self.fetchShortsVideos(suppressOverlay: true)
                    if self.isShowingSearchResults, !self.currentSearchQuery.isEmpty {
                        self.searchVideos(query: self.currentSearchQuery)
                    }
                }
            }
            NotificationCenter.default.post(name: .selectedRegionChanged, object: selectedRegion)
        }
    }
    
    // Kullanıcı channel bilgileri için yeni properties
    @Published var userChannelFromURL: YouTubeChannel?
    @Published var userSubscriptionsFromURL: [YouTubeChannel] = []
    @Published var isLoadingUserData = false
    @Published var userChannelError: String?
    
    // Custom Categories
    @Published var customCategories: [CustomCategory] = [] {
        didSet { persistCustomCategories() }
    }
    @Published var selectedCustomCategoryId: UUID? = nil
    
    init() {
        // Tamamen yerel mod: sadece kullanıcı abonelik ve geçmiş verilerini yükle
        loadSubscriptionsFromUserDefaults()
        loadWatchHistoryFromUserDefaults()
    loadUserPlaylistsFromUserDefaults()
    loadSelectedRegion()
        loadCustomCategories()
    }
    
    // Watch History - Geçmiş
    @Published var watchHistory: [YouTubeVideo] = []
    let maxHistoryItems = 50 // Maksimum geçmiş video sayısı
    
    // Arama durumu takibi
    @Published var isShowingSearchResults = false
    
    // API Key (YouTube Data API v3 için) - Settings ekranından girilir ve UserDefaults'ta saklanır
    @Published var apiKey: String = UserDefaults.standard.string(forKey: "YouTubeAPIKey") ?? "" {
        didSet {
            UserDefaults.standard.set(apiKey, forKey: "YouTubeAPIKey")
        }
    }
    @Published var currentSearchQuery = ""

    // Arama filtreleri
    @Published var activeDateFilter: SearchDateFilter = .none
    @Published var activeDurationFilter: SearchDurationFilter = .none

    // MARK: - Subscriber Count Fetch State (for shimmer + debounce)
    @Published var fetchingSubscriberCountIds: Set<String> = [] // IDs currently in-flight
    // Pending IDs accumulated during debounce window (internal so extension in another file can access)
    var pendingSubscriberRefreshIds: Set<String> = []
    var subscriberRefreshDebounceWorkItem: DispatchWorkItem? = nil
    // One-time logging guards
    var didLogMissingSubscriberAPIKey = false
    var didLogQuotaOrForbidden = false

    // Playlist count refresh queue (official API)
    var pendingPlaylistCountIds: Set<String> = []
    var playlistCountDebounceWorkItem: DispatchWorkItem? = nil
}

extension YouTubeAPIService {
    /// Add a searched (remote) playlist into user's playlists if not already present.
    @MainActor
    func addSearchedPlaylistToUser(_ p: YouTubePlaylist) {
        if userPlaylists.contains(where: { $0.id == p.id }) { return }
        let item = YouTubePlaylist(
            id: p.id,
            title: p.title,
            description: p.description,
            thumbnailURL: p.thumbnailURL,
            videoCount: p.videoCount,
            videoIds: nil, // remote source; items fetched on demand
            coverName: randomPlaylistCoverName(),
            customCoverPath: nil
        )
        userPlaylists.append(item)
        userPlaylists.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
    /// Remove a playlist from user's playlists by id and clear related caches.
    @MainActor
    func removeUserPlaylist(playlistId: String) {
        if let idx = userPlaylists.firstIndex(where: { $0.id == playlistId }) {
            userPlaylists.remove(at: idx)
        }
        // Clear any cached content for the removed playlist
        cachedPlaylistVideos[playlistId] = nil
        totalPlaylistCountById[playlistId] = nil
    }
    /// Ensures the initial home content (trending + shorts + subscriptions) is loaded only once per app session.
    @MainActor
    func performInitialHomeLoadIfNeeded() {
        guard !didPerformInitialHomeLoad else { return }
        didPerformInitialHomeLoad = true
        // Defer actual fetching until region has been resolved to prevent double refresh
        if !didResolveRegion {
            pendingInitialHomeLoad = true
            return
        }
        runInitialHomeLoadNow()
    }

    private func runInitialHomeLoadNow() {
        // Show global overlay to signal initial loading
        showGlobalLoading = true
        fetchHomeRecommendations()
        fetchShortsVideos()
        if !userSubscriptionsFromURL.isEmpty { fetchSubscriptionVideos() }
    }

    private func regionCacheKey() -> CacheKey { CacheKey("preferences:selectedRegion") }

    private func loadSelectedRegion() {
        Task { @MainActor in
            let newValue: String
            if let cached: String = await GlobalCaches.json.get(key: regionCacheKey(), type: String.self) {
                newValue = cached
            } else {
                newValue = "GLOBAL"
            }
            // Only assign if it actually differs to prevent extra refresh on startup
            if newValue != self.selectedRegion {
                self.selectedRegion = newValue
            }
            // Region resolution completed (even if unchanged)
            self.isInitializingRegion = false
            self.didResolveRegion = true
            // If initial load was requested earlier, perform it now exactly once
            if self.pendingInitialHomeLoad {
                self.pendingInitialHomeLoad = false
                self.runInitialHomeLoadNow()
            }
        }
    }

    private func persistSelectedRegion() async {
        await GlobalCaches.json.set(key: regionCacheKey(), value: selectedRegion, ttl: CacheTTL.sevenDays * 52) // ~1 year
    }

    /// Returns (hl, gl) strings to use for requests based on selectedRegion.
    /// If Global is selected, fall back to app language for hl.
    func currentLocaleParams() -> (hl: String, gl: String?) {
        let gl: String? = (selectedRegion == "GLOBAL") ? nil : selectedRegion
        let hl = LanguageResources.preferredHL(for: gl)
        return (hl, gl)
    }
    // MARK: - Custom Categories Persistence
    private func customCategoriesCacheKey() -> CacheKey { CacheKey("preferences:customCategories") }

    private func loadCustomCategories() {
        Task { @MainActor in
            if let decoded: [CustomCategory] = await GlobalCaches.json.get(key: customCategoriesCacheKey(), type: [CustomCategory].self) {
                self.customCategories = decoded
            }
        }
    }

    private func persistCustomCategories() {
        let value = customCategories
        Task { await GlobalCaches.json.set(key: customCategoriesCacheKey(), value: value, ttl: CacheTTL.sevenDays * 52) }
    }

    // MARK: - Build query for a custom category
    private func buildQuery(for custom: CustomCategory) -> String {
        var parts: [String] = []
        let primary = custom.primaryKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if !primary.isEmpty { parts.append(primary) }
        for opt in [custom.secondaryKeyword, custom.thirdKeyword, custom.fourthKeyword] {
            if let s = opt, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parts.append(s) }
        }
        return parts.joined(separator: " ")
    }

    // MARK: - Fetch videos for Custom Category (local search adapter only)
    func fetchVideos(for custom: CustomCategory, suppressOverlay: Bool = false, forceRefresh: Bool = false) {
        print("🎯 Fetch custom category: \(custom.name) -> \(custom.primaryKeyword) \(custom.secondaryKeyword ?? "")")
        isLoadingVideos = true
        isLoading = isLoadingVideos || isLoadingShorts
        if !suppressOverlay { showGlobalLoading = true }
        isShowingSearchResults = false
    selectedCustomCategoryId = custom.id
    // Also reseed Shorts based on this custom category so the Shorts rail matches the filter
    fetchShortsVideos(suppressOverlay: true, forceRefresh: true)
        let query = buildQuery(for: custom)
        let startLocale = self.currentLocaleParams()
        let token = UUID()
        self.categoryFetchToken = token
    Task { @MainActor in
            do {
                // Gather results from multiple variations until we have >= 30 after filters
                var allResults: [YouTubeVideo] = []
                var seen = Set<String>()
                // Build query candidates via centralized builder (same behavior)
                let candidates = QueryBuilder.buildCustomCategoryQueries(hl: startLocale.hl, gl: startLocale.gl, custom: custom)

                func applyStrictFilters(_ items: [YouTubeVideo]) -> [YouTubeVideo] {
                    var filtered = items
                    // Remove shorts-like items for long video feeds
                    filtered = filtered.filter { !$0.title.lowercased().contains("shorts") && !isUnderOneMinute($0) }
                    // Date filter (strict)
                    if let cutoff = custom.dateFilter.cutoffDate {
                        filtered = filtered.compactMap { v in
                            if let d = v.publishedAtISODate { return d >= cutoff ? v : nil }
                            let (_, iso) = self.normalizePublishedAt(v.publishedAt, iso: v.publishedAtISO)
                            if let iso, let dd = ISO8601DateFormatter().date(from: iso), dd >= cutoff {
                                return YouTubeVideo(id: v.id, title: v.title, channelTitle: v.channelTitle, channelId: v.channelId, viewCount: v.viewCount, publishedAt: v.publishedAt, publishedAtISO: iso, thumbnailURL: v.thumbnailURL, description: v.description, channelThumbnailURL: v.channelThumbnailURL, likeCount: v.likeCount, durationText: v.durationText, durationSeconds: v.durationSeconds)
                            }
                            return nil
                        }
                    }
                    return filtered
                }

                // Sequentially fetch candidates until we have enough
                for q in candidates {
                    let items = try await LocalSearchAdapter.search(query: q, hl: startLocale.hl, gl: startLocale.gl, bypassCache: forceRefresh)
                    let filtered = applyStrictFilters(items)
                    for v in filtered where seen.insert(v.id).inserted { allResults.append(v) }
                    if allResults.count >= 30 { break }
                    // Check token/locale mid-loop to avoid wasted work
                    let current = self.currentLocaleParams()
                    if self.categoryFetchToken != token || current.hl != startLocale.hl || current.gl != startLocale.gl {
                        print("⏭️ Aborting custom category accumulation (locale/token changed)")
                        return
                    }
                }

                // Fallback: if results are still too few (<= 6), reduce language/region influence
                if allResults.count <= 6 {
                    print("ℹ️ Low custom-category results (\(allResults.count)). Running region-agnostic fallback…")
                    var fallback: [String] = []
                    // Prefer very broad queries without region name bias (preserve behavior)
                    let primary = custom.primaryKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
                    let extras = [custom.secondaryKeyword, custom.thirdKeyword, custom.fourthKeyword]
                        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    fallback.append(primary)
                    if !primary.isEmpty { fallback.append("\(primary) video") }
                    for e in extras { fallback.append(e); fallback.append("\(e) video") }
                    // De-duplicate, skip ones already tried
                    let tried = Set(candidates.map { $0.lowercased() })
                    var fallbackDedup: [String] = []
                    var seenQ = Set<String>()
                    for q in fallback {
                        let key = q.lowercased()
                        if tried.contains(key) { continue }
                        if seenQ.insert(key).inserted { fallbackDedup.append(q) }
                    }
                    for q in fallbackDedup {
                        let items = try await LocalSearchAdapter.search(query: q, hl: startLocale.hl, gl: nil, bypassCache: forceRefresh)
                        // Apply the same strict filters (keeps date cutoff & removes shorts), but avoid region-name bias
                        let filtered = applyStrictFilters(items)
                        for v in filtered where seen.insert(v.id).inserted { allResults.append(v) }
                        if allResults.count >= 30 { break }
                        let current = self.currentLocaleParams()
                        if self.categoryFetchToken != token || current.hl != startLocale.hl || current.gl != startLocale.gl {
                            print("⏭️ Aborting fallback accumulation (locale/token changed)")
                            return
                        }
                    }
                }

                allResults.shuffle()
                let top = Array(allResults.prefix(30))
                let current = self.currentLocaleParams()
                guard self.categoryFetchToken == token, current.hl == startLocale.hl, current.gl == startLocale.gl else {
                    print("⏭️ Ignoring stale custom category results (locale/token changed)")
                    return
                }
                self.videos = top
                if !top.isEmpty { self.fetchChannelThumbnails(for: top) }
            } catch {
                print("⚠️ Custom category fetch failed: \(error)")
                self.videos = []
            }
            self.isLoadingVideos = false
            self.isLoading = self.isLoadingVideos || self.isLoadingShorts
            self.showGlobalLoading = false
        }
    }
}

// MARK: - Home recommendations from Watch History
extension YouTubeAPIService {
    /// Build Home recommendations by analyzing recent watch history (channels and frequent terms), honoring region.
    func fetchHomeRecommendations(suppressOverlay: Bool = false) {
        print("🏠 Home recommendations from watch history")
        isLoadingVideos = true
        isLoading = isLoadingVideos || isLoadingShorts
        if !suppressOverlay { showGlobalLoading = true }
        isShowingSearchResults = false
    selectedCustomCategoryId = nil
        let startLocale = self.currentLocaleParams()
        let token = UUID()
        self.categoryFetchToken = token
        let snapshot = Array(self.watchHistory.prefix(25))
        Task { @MainActor in
            do {
                var seeds: [String] = []
                // Frequent channels
                var channelFreq: [String: Int] = [:]
                for v in snapshot { channelFreq[v.channelTitle, default: 0] += 1 }
                let topChannels = channelFreq.sorted { $0.value > $1.value }.prefix(3).map { $0.key }
                seeds.append(contentsOf: topChannels)
                // Frequent keywords from titles
        func extractKeywords(_ text: String, lang: String) -> [String] {
                    let lower = text.lowercased()
                    var tokens: [String] = []
                    let tagger = NLTagger(tagSchemes: [.lexicalClass])
                    tagger.string = lower
                    tagger.setLanguage(NLLanguage(rawValue: lang), range: lower.startIndex..<lower.endIndex)
                    let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]
                    tagger.enumerateTags(in: lower.startIndex..<lower.endIndex, unit: .word, scheme: .lexicalClass, options: options) { tag, range in
            if let tag = tag, (tag == .noun || tag == .verb || tag == .adjective || tag == .adverb || tag == .otherWord) {
                            tokens.append(String(lower[range]))
                        }
                        return true
                    }
                    if tokens.isEmpty { tokens = lower.components(separatedBy: CharacterSet.alphanumerics.inverted) }
                    let stop = LanguageResources.stopwords(for: lang)
                    return tokens.filter { $0.count > 2 && !stop.contains($0) }
                }
                var freq: [String: Int] = [:]
                for v in snapshot { for w in extractKeywords(v.title, lang: startLocale.hl) { freq[w, default: 0] += 1 } }
                let topWords = freq.sorted { $0.value > $1.value }.prefix(6).map { $0.key }
                seeds.append(contentsOf: topWords)
                // Build diverse queries via centralized QueryBuilder (behavior preserved)
                var queries = QueryBuilder.buildHomeSeedQueries(hl: startLocale.hl, gl: startLocale.gl, topChannels: topChannels, topWords: topWords).shuffled()
                var all: [YouTubeVideo] = []
                for q in queries.prefix(3) {
                    let items = try await LocalSearchAdapter.search(query: q, hl: startLocale.hl, gl: startLocale.gl)
                    all.append(contentsOf: items)
                }
                var seen = Set<String>()
                let longOnly = all.filter { !$0.title.lowercased().contains("shorts") && !isUnderOneMinute($0) && seen.insert($0.id).inserted }
                let final = Array(longOnly.shuffled().prefix(30))
                let current = self.currentLocaleParams()
                guard self.categoryFetchToken == token, current.hl == startLocale.hl, current.gl == startLocale.gl else {
                    print("⏭️ Ignoring stale home results (locale/token changed); relying on region-change refresh")
                    return
                }
                self.videos = final
                if !final.isEmpty { self.fetchChannelThumbnails(for: final) }
                // Reset empty-home retry flag when we have data
                if !final.isEmpty { self.didRetryEmptyHome = false }
            } catch {
                print("⚠️ Home recommendations failed: \(error)")
                self.videos = []
            }
            self.isLoadingVideos = false
            self.isLoading = self.isLoadingVideos || self.isLoadingShorts
            self.showGlobalLoading = false
            // If still empty on first launch due to race (cookies/locale), do a one-time retry shortly after
            if self.videos.isEmpty && !self.didRetryEmptyHome {
                self.didRetryEmptyHome = true
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    self.fetchHomeRecommendations(suppressOverlay: true)
                }
            }
        }
    }

    fileprivate func stopwords(for lang: String) -> Set<String> {
        // Merkezileştirildi: LanguageResources üzerinden döndür
        return LanguageResources.stopwords(for: lang)
    }
}

extension Notification.Name {
    static let selectedRegionChanged = Notification.Name("SelectedRegionChanged")
}

// MARK: - Cookie management for region changes
extension YouTubeAPIService {
    /// Clear all YouTube/Google cookies and set fresh region cookies (PREF hl/gl, plus consent bypass) for the given locale.
    fileprivate func resetYouTubeCookies(hl: String, gl: String?) async {
        let storage = HTTPCookieStorage.shared
        let domains = ["youtube.com", ".youtube.com", "google.com", ".google.com"]
        for c in storage.cookies ?? [] {
            if domains.contains(where: { c.domain.hasSuffix($0) || c.domain == $0 }) {
                storage.deleteCookie(c)
            }
        }
        // Prepare helper to insert a cookie
        func setCookie(domain: String, name: String, value: String) {
            let props: [HTTPCookiePropertyKey: Any] = [
                .domain: domain,
                .path: "/",
                .name: name,
                .value: value,
                .secure: true,
                .expires: Date(timeIntervalSinceNow: 60 * 60 * 24 * 365) // ~1 year
            ]
            if let cookie = HTTPCookie(properties: props) { storage.setCookie(cookie) }
        }
        // Always set consent bypass so HTML endpoints don't block with interstitials
        for d in [".youtube.com", ".google.com"] {
            setCookie(domain: d, name: "CONSENT", value: "YES+")
            setCookie(domain: d, name: "SOCS", value: "CAI")
        }
        // Region preference cookie
        let pref: String = {
            if let g = gl { return "hl=\(hl)&gl=\(g)" }
            return "hl=\(hl)"
        }()
        for d in [".youtube.com", ".google.com"] { setCookie(domain: d, name: "PREF", value: pref) }
    }
}

extension YouTubeAPIService {
    /// Herhangi bir listede (ana videolar, kategori cache'i, abonelikler, shorts, geçmiş, ilgili) verilen id'ye sahip videoyu bulur.
    func findVideo(by id: String) -> YouTubeVideo? {
        if let v = videos.first(where: { $0.id == id }) { return v }
        if let v = subscriptionVideos.first(where: { $0.id == id }) { return v }
        if let v = shortsVideos.first(where: { $0.id == id }) { return v }
        if let v = watchHistory.first(where: { $0.id == id }) { return v }
        if let v = relatedVideos.first(where: { $0.id == id }) { return v }
        
        if let v = currentChannelPopularVideos.first(where: { $0.id == id }) { return v }
        if let v = channelVideos.first(where: { $0.id == id }) { return v }
        if let v = playlistVideos.first(where: { $0.id == id }) { return v }
        return nil
    }
}

// MARK: - Cache Management
extension YouTubeAPIService {
    func clearImageCache() {
        Task { await GlobalCaches.images.clear() }
    }
    func clearDataCache() {
        Task {
            // Preserve preferences before clearing json cache
            let savedRegion: String? = await GlobalCaches.json.get(key: regionCacheKey(), type: String.self)
            let savedCategories: [CustomCategory]? = await GlobalCaches.json.get(key: customCategoriesCacheKey(), type: [CustomCategory].self)

            // Clear all data caches used for searches/lists
            await GlobalCaches.json.clear()

            // Restore preserved preferences so user settings remain
            if let sr = savedRegion {
                await GlobalCaches.json.set(key: regionCacheKey(), value: sr, ttl: CacheTTL.sevenDays * 52)
            }
            if let cats = savedCategories {
                await GlobalCaches.json.set(key: customCategoriesCacheKey(), value: cats, ttl: CacheTTL.sevenDays * 52)
            }
        }
    }

    /// Uygulamadaki tüm verileri temizle: disk önbellekler (json+image), URLCache, izleme geçmişi, abonelikler, listeler.
    @MainActor
    func clearAllData() {
        // 1) Disk cache'leri temizle
        Task { await GlobalCaches.images.clear() }
        Task { await GlobalCaches.json.clear() }

        // 2) URLCache temizle
        URLCache.shared.removeAllCachedResponses()

        // 3) İzleme geçmişi temizle (state + UserDefaults)
        clearWatchHistory()

        // 4) Abonelikleri temizle (state + UserDefaults)
        clearSubscriptions()

        // 5) Çeşitli listeleri ve geçici state'leri sıfırla
        videos.removeAll()
        shortsVideos.removeAll()
        subscriptionVideos.removeAll()
        relatedVideos.removeAll()
        currentChannelPopularVideos.removeAll()
        channelVideos.removeAll()
        playlistVideos.removeAll()
    userPlaylists.removeAll()
        
        likeCountByVideoId.removeAll()

        // 6) Kullanıcı kanal bilgisini sıfırla ki Sidebar abonelik bloğunu gizlesin
        userChannelFromURL = nil
        userChannelError = nil
        isLoadingUserData = false
    }

    /// Abonelik listesini tamamen temizle ve UserDefaults'tan kaldır
    @MainActor
    func clearSubscriptions() {
        userSubscriptionsFromURL.removeAll()
        subscriptionVideos.removeAll()
        UserDefaults.standard.removeObject(forKey: "userSubscriptions")
        UserDefaults.standard.synchronize()
    }
}

// MARK: - Playlists (CSV import) persistence and helpers
extension YouTubeAPIService {
    private func saveUserPlaylistsToUserDefaults() {
        let enc = JSONEncoder()
        if let data = try? enc.encode(userPlaylists) {
            UserDefaults.standard.set(data, forKey: "userPlaylists")
            UserDefaults.standard.synchronize()
        }
    }

    func loadUserPlaylistsFromUserDefaults() {
        if let data = UserDefaults.standard.data(forKey: "userPlaylists"),
           let decoded = try? JSONDecoder().decode([YouTubePlaylist].self, from: data) {
            // Backfill: eski kayıtlarda coverName olmayabilir – açarken atayalım
            let withCovers: [YouTubePlaylist] = decoded.map { p in
                if p.coverName != nil || p.customCoverPath != nil { return p }
                let name = self.randomPlaylistCoverName()
                return YouTubePlaylist(id: p.id, title: p.title, description: p.description, thumbnailURL: p.thumbnailURL, videoCount: p.videoCount, videoIds: p.videoIds, coverName: name, customCoverPath: nil)
            }
            userPlaylists = withCovers
        }
    }

    /// Add a video to a user playlist (local). Creates the videoIds array if needed and updates videoCount.
    @MainActor
    func addVideo(_ videoId: String, toPlaylistId playlistId: String) {
        guard let idx = userPlaylists.firstIndex(where: { $0.id == playlistId }) else { return }
        let p = userPlaylists[idx]
        var ids = p.videoIds ?? []
        if ids.contains(videoId) { return }
        ids.append(videoId)
        let updated = YouTubePlaylist(
            id: p.id,
            title: p.title,
            description: p.description,
            thumbnailURL: p.thumbnailURL,
            videoCount: ids.count,
            videoIds: ids,
            coverName: p.coverName,
            customCoverPath: p.customCoverPath
        )
        userPlaylists[idx] = updated
    }

    /// Create a new local playlist with a random default cover. Optionally seed with a first video.
    @MainActor
    @discardableResult
    func createUserPlaylist(title rawTitle: String, firstVideoId: String? = nil) -> YouTubePlaylist? {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let id = "LOCAL_" + UUID().uuidString
        var ids: [String]? = nil
        if let vid = firstVideoId { ids = [vid] }
        let cover = randomPlaylistCoverName()
        let playlist = YouTubePlaylist(
            id: id,
            title: title,
            description: "",
            thumbnailURL: "",
            videoCount: ids?.count ?? 0,
            videoIds: ids,
            coverName: cover,
            customCoverPath: nil
        )
        userPlaylists.append(playlist)
        userPlaylists.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return playlist
    }

    /// Rename a user playlist's title by id and persist to UserDefaults.
    @MainActor
    func renamePlaylist(playlistId: String, to newTitle: String) {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        guard let idx = userPlaylists.firstIndex(where: { $0.id == playlistId }) else { return }
        let p = userPlaylists[idx]
        let updated = YouTubePlaylist(
            id: p.id,
            title: title,
            description: p.description,
            thumbnailURL: p.thumbnailURL,
            videoCount: p.videoCount,
            videoIds: p.videoIds,
            coverName: p.coverName,
            customCoverPath: p.customCoverPath
        )
        userPlaylists[idx] = updated
    }

    /// Accept playlist URLs or IDs (and optionally inline video IDs), normalize to IDs, and create minimal playlist entries.
    /// If tokens are pure video IDs/URLs, they are grouped under a synthetic playlist using the CSV file name (passed via special first token "__CSV_FILENAME__=...").
    @MainActor
    func importPlaylists(from urlsOrIds: [String]) {
        var added: [YouTubePlaylist] = []
        var csvName: String? = nil
        var collectedVideoIds: [String] = []
        for token in urlsOrIds {
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            // Özel: ilk satır dosya adını taşıyabilir
            if trimmed.hasPrefix("__CSV_FILENAME__=") {
                let raw = String(trimmed.split(separator: "=", maxSplits: 1).last ?? "")
                csvName = raw.replacingOccurrences(of: ".csv", with: "")
                continue
            }
            if let listId = extractPlaylistId(from: trimmed) {
                if userPlaylists.contains(where: { $0.id == listId }) { continue }
                let titleGuess = csvName ?? "Playlist \(userPlaylists.count + added.count + 1)"
                let p = YouTubePlaylist(id: listId, title: titleGuess, description: "", thumbnailURL: "", videoCount: 0, videoIds: nil, coverName: randomPlaylistCoverName(), customCoverPath: nil)
                added.append(p)
            } else if let vid = extractVideoId(from: trimmed) {
                collectedVideoIds.append(vid)
            }
        }
        // Eğer playlist ID bulunamadı ama video ID’leri toplandıysa, dosya adından sentetik bir playlist oluştur
        if added.isEmpty && !collectedVideoIds.isEmpty {
            let title = (csvName?.isEmpty == false) ? csvName! : "Playlist \(userPlaylists.count + 1)"
            // Sentetik playlist id: CSV adı + hash
            let syntheticId = "CSV_" + (title.replacingOccurrences(of: " ", with: "_"))
            let p = YouTubePlaylist(id: syntheticId, title: title, description: "", thumbnailURL: "", videoCount: collectedVideoIds.count, videoIds: collectedVideoIds, coverName: randomPlaylistCoverName(), customCoverPath: nil)
            added.append(p)
        }
        if !added.isEmpty {
            userPlaylists.append(contentsOf: added)
            userPlaylists.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }

    /// Random cover picker from bundled Examples images; returns logical base name without extension
    func randomPlaylistCoverName() -> String {
    // Known options in Examples. Include both the correct and historical misspelled variant for compatibility.
    let candidates = ["playlist", "playlist2", "playlist3", "playlist4"]
        return candidates.randomElement() ?? "playlist"
    }

    /// Best-effort playlist id extraction from various YouTube URL forms.
    func extractPlaylistId(from raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
    // If looks like an ID (PL..., LL..., UU..., OL..., FL..., WL, RD...)
    if s.count >= 10 && (s.hasPrefix("PL") || s.hasPrefix("LL") || s.hasPrefix("UU") || s.hasPrefix("OL") || s.hasPrefix("FL") || s.hasPrefix("RD") || s == "WL") {
            return s
        }
        guard let url = URL(string: s) else { return nil }
        // youtube.com/playlist?list=...
        if url.path.contains("/playlist") || url.path.contains("/watch") || url.host?.contains("youtube.com") == true {
            if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                if let q = comps.queryItems?.first(where: { $0.name == "list" })?.value, !q.isEmpty {
                    return q
                }
            }
            // Shorts or others rarely include list in path; attempt path scanning
            let path = url.path
            // fallback: /playlist/PLxxxx (rare)
            if let range = path.range(of: "PL", options: .caseInsensitive) {
                let candidate = String(path[range.lowerBound...])
                if candidate.count >= 10 { return candidate }
            }
        }
        return nil
    }

    /// Best-effort video id extraction from various YouTube URL forms.
    func extractVideoId(from raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        // Likely raw id
        if s.count == 11, s.range(of: "^[a-zA-Z0-9_-]{11}$", options: .regularExpression) != nil { return s }
        guard let url = URL(string: s) else { return nil }
        if url.host?.contains("youtube.com") == true || url.host?.contains("youtu.be") == true {
            if url.host?.contains("youtu.be") == true {
                let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if path.count == 11 { return path }
            }
            if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                if let v = comps.queryItems?.first(where: { $0.name == "v" })?.value, v.count == 11 { return v }
            }
            // /shorts/<id>
            let parts = url.path.split(separator: "/").map(String.init)
            if parts.count >= 2, parts[0].lowercased() == "shorts", parts[1].count == 11 { return parts[1] }
        }
        return nil
    }

    // İlk yükleme için varsayılan 40 video; gerektiğinde artan dilimde yükler
    func loadPlaylistVideosIfNeeded(playlist: YouTubePlaylist, limit: Int = 40) async {
        // If cache has real content (not just placeholder rows), skip; otherwise ensure at least `limit` are loaded
        if let cached = cachedPlaylistVideos[playlist.id], !cached.isEmpty {
            let allPlaceholders = cached.allSatisfy { $0.title.isEmpty && $0.channelTitle.isEmpty }
            if !allPlaceholders { return }
            // else: fall through to load real items to replace placeholders
        }
        await ensurePlaylistLoadedCount(playlist: playlist, minCount: limit)
    }

    /// Ensure at least minCount items are loaded into cachedPlaylistVideos[playlist.id].
    /// - For remote playlists (no inline videoIds), uses LocalPlaylistAdapter.fetchVideos with increasing limit.
    /// - For local playlists (videoIds present), fetch metadata for the next slice and append.
    func ensurePlaylistLoadedCount(playlist: YouTubePlaylist, minCount: Int) async {
        let key = playlist.id
    // Count only real loaded items (placeholders have empty title+channel)
    let existing = cachedPlaylistVideos[key] ?? []
    let currentRealCount = existing.filter { !($0.title.isEmpty && $0.channelTitle.isEmpty) }.count
    // Fast path: if we already have at least some items but their display fields (view/date) are empty,
    // enrich the first few items in-place before deciding to early-return.
    if !existing.isEmpty {
        let prefix = max(1, min(6, min(minCount, existing.count)))
        var indexesToEnrich: [Int] = []
        for i in 0..<prefix {
            let v = existing[i]
            if v.viewCount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || v.publishedAt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                indexesToEnrich.append(i)
            }
        }
        if !indexesToEnrich.isEmpty {
            let enriched: [(Int, YouTubeVideo)] = await self.enrichVideos(items: existing, indices: indexesToEnrich)
            if !enriched.isEmpty {
                await MainActor.run {
                    var base = self.cachedPlaylistVideos[key] ?? existing
                    if base.isEmpty { base = existing }
                    for (i, v) in enriched { if i < base.count { base[i] = v } }
                    self.cachedPlaylistVideos[key] = base
                }
            }
        }
        // If we already have enough real items loaded, we can return now (after potential enrichment above).
        if currentRealCount >= minCount { return }
    }

        if let vids = playlist.videoIds, !vids.isEmpty {
            // Local playlist: expand by fetching metadata for missing slice
        await MainActor.run { self.totalPlaylistCountById[key] = vids.count }
        let locale = currentLocaleParams()
        let sliceEnd = min(minCount, vids.count)
        let missingRange = currentRealCount..<sliceEnd
            if missingRange.isEmpty { return }
            let ids = Array(vids[missingRange])
            let newItems: [YouTubeVideo] = await withTaskGroup(of: (Int, YouTubeVideo?).self, returning: [YouTubeVideo].self) { group in
                for (offset, vid) in ids.enumerated() {
            let idx = currentRealCount + offset
                    group.addTask {
                        do {
                            let meta = try await self.fetchVideoMetadata(videoId: vid, hl: locale.hl, gl: locale.gl)
                            let (displayDate, isoGuess) = self.normalizePublishedAt(meta.publishedTimeText)
                            let displayViews = self.normalizeViewCount(meta.viewCountText)
                            let v = YouTubeVideo(
                                id: meta.id,
                                title: meta.title,
                                channelTitle: meta.author,
                                channelId: meta.channelId ?? "",
                                viewCount: displayViews,
                                publishedAt: displayDate,
                                publishedAtISO: isoGuess,
                                thumbnailURL: youtubeThumbnailURL(meta.id, quality: .hqdefault),
                                description: meta.effectiveDescription,
                                channelThumbnailURL: "",
                                likeCount: "0",
                                durationText: meta.durationText,
                                durationSeconds: meta.durationSeconds
                            )
                            return (idx, v)
                        } catch {
                            return (idx, nil)
                        }
                    }
                }
                var collected: [(Int, YouTubeVideo)] = []
                for await (idx, v) in group { if let v = v { collected.append((idx, v)) } }
                collected.sort { $0.0 < $1.0 }
                return collected.map { $0.1 }
            }
            await MainActor.run {
                var base = cachedPlaylistVideos[key] ?? []
                // If base has placeholders for count, replace in place
                if !base.isEmpty, base.allSatisfy({ $0.title.isEmpty && $0.channelTitle.isEmpty }) {
                    // Ensure capacity
                    if base.count < sliceEnd { base = Array(repeating: base.first!, count: sliceEnd) }
                    // Fill the new range
                    for (i, item) in newItems.enumerated() { base[currentRealCount + i] = item }
                    cachedPlaylistVideos[key] = base
                } else {
                    base.append(contentsOf: newItems)
                    cachedPlaylistVideos[key] = base
                }
            }
        } else {
            // Remote playlist: ask adapter for a larger prefix and assign
            do {
                var items = try await LocalPlaylistAdapter.fetchVideos(playlistId: key, limit: minCount)
                // Enrich the first few items with view/date using the same local metadata path used on homepage
                // Prioritize at least the first item (affects the video panel immediately). Cap enrichment to a small number for performance.
                let enrichCount = max(1, min(6, items.count))
                if enrichCount > 0 {
                    let enriched = await self.enrichFirst(items: items, maxCount: enrichCount)
                    // Merge enriched items back into the list
                    for (i, v) in enriched { items[i] = v }
                }
                let snapshotItems = items // snapshot for Swift 6 concurrency safety
                await MainActor.run { self.cachedPlaylistVideos[key] = snapshotItems }
            } catch {
                // If we only had placeholders, clear them to avoid endless spinner in UI
                await MainActor.run {
                    if let existing = self.cachedPlaylistVideos[key], existing.allSatisfy({ $0.title.isEmpty && $0.channelTitle.isEmpty }) {
                        self.cachedPlaylistVideos[key] = []
                    }
                    self.error = "Playlist load failed"
                }
            }
        }
    }

    /// Ensure at least minCount items for a playlist by id, even if not present in userPlaylists.
    /// This mirrors the behavior of `ensurePlaylistLoadedCount(playlist:minCount:)` for the
    /// remote playlist path and delegates to the playlist-based overload when possible.
    @MainActor
    func ensurePlaylistLoadedCount(playlistId: String, minCount: Int) async {
        // If we have a concrete playlist object (e.g., a local user playlist), delegate to the typed version
        if let p = userPlaylists.first(where: { $0.id == playlistId }) {
            await ensurePlaylistLoadedCount(playlist: p, minCount: minCount)
            return
        }
        let key = playlistId
        let existing = cachedPlaylistVideos[key] ?? []
        let currentRealCount = existing.filter { !($0.title.isEmpty && $0.channelTitle.isEmpty) }.count
        // If we already have enough real items, nothing to do
        if currentRealCount >= minCount { return }
        do {
            var items = try await LocalPlaylistAdapter.fetchVideos(playlistId: key, limit: minCount)
            // Enrich the first few items with view/date like the typed overload
            let enrichCount = max(1, min(6, items.count))
            if enrichCount > 0 {
                let enriched = await self.enrichFirst(items: items, maxCount: enrichCount)
                for (i, v) in enriched { items[i] = v }
            }
            let snapshotItems = items
            await MainActor.run { self.cachedPlaylistVideos[key] = snapshotItems }
        } catch {
            await MainActor.run {
                if let existing = self.cachedPlaylistVideos[key], existing.allSatisfy({ $0.title.isEmpty && $0.channelTitle.isEmpty }) {
                    self.cachedPlaylistVideos[key] = []
                }
                self.error = "Playlist load failed"
            }
        }
    }
}

// MARK: - Playlist cover helpers moved to Services/PlaylistCoverService.swift

// MARK: - Like Count Fetch (Data API)
extension YouTubeAPIService {
    func fetchLikeCountIfNeeded(videoId: String) {
        if let existing = likeCountByVideoId[videoId], !existing.isEmpty { return }
        fetchVideoDetails(videoId: videoId)
    }

    /// Canlı yayınlar için izleyici sayısını tek seferlik çek ve cache'le.
    func fetchLiveViewersIfNeeded(videoId: String) {
        // İstek: cache olmasın, her görünümde tazele
        if fetchingLiveViewers.contains(videoId) { return }
        fetchingLiveViewers.insert(videoId)
        Task { [weak self] in
            guard let self = self else { return }
            defer { self.fetchingLiveViewers.remove(videoId) }
            do {
                let meta = try await self.fetchVideoMetadata(videoId: videoId)
                // Ham metin: "12,345 watching now" gibi
                let raw = meta.rawViewCountText
                if let formatted = self.parseWatchingCount(rawText: raw) {
                    await MainActor.run { self.liveViewersByVideoId[videoId] = formatted }
                }
            } catch {
                // Sessizce yok say – canlı olmayan videolarda başarısız olabilir
            }
        }
    }

    /// Ham metinden yalnızca "... watching (now)" / "... izleyici" ifadesine BİTİŞİK sayıyı çıkar ve kısa format döndür.
    private func parseWatchingCount(rawText: String) -> String? {
        let text = rawText
        // 1) Öncelik: sayı (opsiyonel K/M/B/Mn) + boşluk + (watching now|watching|izleyici)
        let pattern1 = #"(?i)([0-9][0-9\s.,]*?(?:\.[0-9])?\s*(?:K|M|B|Mn)?)\s*(watching now|watching|izleyici)"#
        // 2) İkinci öncelik: (watching now|watching|izleyici) + boşluk + sayı
        let pattern2 = #"(?i)(watching now|watching|izleyici)\s*([0-9][0-9\s.,]*?(?:\.[0-9])?\s*(?:K|M|B|Mn)?)"#

        func extract(_ pattern: String, takeGroup: Int) -> Int? {
            guard let re = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
            let ns = text as NSString
            if let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges > takeGroup {
                let r = m.range(at: takeGroup)
                if r.location != NSNotFound, let range = Range(r, in: text) {
                    let token = String(text[range])
                    if let n = approxNumberFromText(token) { return n }
                }
            }
            return nil
        }

        // Sırasıyla dene
        if let n = extract(pattern1, takeGroup: 1) { return sanitizeLiveCount(n) }
        if let n = extract(pattern2, takeGroup: 2) { return sanitizeLiveCount(n) }

        // 3) Anahtar yoksa veya regex kaçırdıysa: başarısız
        return nil
    }

    /// Gerçekçi olmayan aşırı yüksek sayıları eler (yanlış kaynaktan gelen 70M gibi); yoksa kısa format döndürür.
    private func sanitizeLiveCount(_ n: Int) -> String? {
        // Canlı eşzamanlı izleyici sayısının pratik üst sınırı (emniyet payıyla)
        if n > 5_000_000 { return nil }
        return formatCountShort(String(n))
    }
}

struct MainAppView: View {
    var body: some View {
        MainContentView()
    }
}

#Preview {
    MainAppView()
}