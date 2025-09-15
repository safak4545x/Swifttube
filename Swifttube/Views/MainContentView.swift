/*
 Overview / Genel Bakış
 EN: Primary UI container: native sidebar, main content, search toolbar, overlays (video panel, tabs), and global loading/error layers.
 TR: Ana UI konteyneri: yerel yan menü, ana içerik, arama araç çubuğu, katmanlar (video paneli, sekmeler) ve global yükleme/hata katmanları.
*/

// EN: SwiftUI for UI, AppKit for toolbar search field. TR: UI için SwiftUI, araç çubuğu araması için AppKit.
import SwiftUI
import AppKit

struct MainContentView: View {
    // EN: Localization provider. TR: Yerelleştirme sağlayıcısı.
    @EnvironmentObject var i18n: Localizer
    // EN: Tab manager for multi-tab video content. TR: Çoklu sekme video içeriği için sekme yöneticisi.
    @EnvironmentObject private var tabs: TabCoordinator
    // EN: Selected channel and its sheet visibility. TR: Seçili kanal ve panel görünürlüğü.
    @State private var selectedChannel: YouTubeChannel? = nil
    @State private var showChannelSheet: Bool = false
    // EN: Current page selection and URL. TR: Geçerli sayfa seçimi ve URL.
    @State private var selectedSidebarId: String = sidebarItems.first!.id
    @State private var currentURL: String = sidebarItems.first!.url
    // EN: Toolbar search text. TR: Araç çubuğu arama metni.
    @State private var searchText: String = ""
    // EN: Currently opened overlay video (inline panel). TR: Şu anda açık olan video paneli.
    @State private var selectedVideo: YouTubeVideo? = nil
    // EN: Resume position when returning from PiP (seconds). TR: PiP dönüşünde kaldığı yer (saniye).
    @State private var pendingResumeTime: Double? = nil
    // EN: Shorts rail UI state (comments + index). TR: Shorts şeridi UI durumu (yorumlar + indeks).
    @State private var showShortsComments = false
    @State private var currentShortsIndex = 0
    // EN: Central app service for data and orchestration. TR: Veri ve orkestrasyon için merkezi servis.
    @StateObject private var youtubeAPI = YouTubeAPIService()
    // EN: Sidebar UI state (selection/persist). TR: Sidebar UI durumu (seçim/kalıcılık).
    @StateObject private var sidebarState = SidebarState()
        // EN: Background audio-only playlist player. TR: Arka plan ses-only playlist oynatıcı.
        @StateObject private var audioPlayer = AudioPlaylistPlayer()

    // EN: Persist last selected video in playlist mode. TR: Playlist modunda son seçili videoyu sakla.
    @State private var playlistModeSelectedVideoId: String? = nil
    // EN: Overlay playlist context (non-tab) opened via left-click. TR: Sol tıkla açılan kaplama playlist bağlamı (sekme değil).
    @State private var overlayPlaylistContext: PlaylistContext? = nil

    // EN: Search-related sheet states and selection. TR: Arama ile ilgili sheet durumları ve seçim.
    @State private var showChannelSearch = false
    @State private var showPlaylistSearch = false
    @State private var selectedPlaylist: YouTubePlaylist? = nil
    @State private var showChannelView = false
    @State private var showPlaylistView = false
    // EN: Bottom mini audio-player bar visibility. TR: Alt mini ses çubuğu görünürlüğü.
    @State private var showBottomPlayerBar: Bool = false
    
    // EN: Manual user channel URL input flow. TR: Elle kullanıcı kanal URL girişi akışı.
    @State private var showUserChannelInput = false
    @State private var userChannelURL = ""

    var body: some View {
    // EN: Two-pane macOS split view: sidebar + detail. TR: İki panelli macOS bölünmüş görünümü: yan menü + detay.
    NavigationSplitView {
            // EN: Native Apple Sidebar. TR: Yerel Apple yan menüsü.
            nativeSidebar
        } detail: {
            // EN: Main content area wrapped with shared sheet manager. TR: Ortak panel yöneticisi ile sarılmış ana içerik alanı.
            SheetManagementView(
                content: nativeMainContent,
                selectedVideo: $selectedVideo,
                showChannelSheet: $showChannelSheet,
                selectedChannel: $selectedChannel,
                showChannelSearch: $showChannelSearch,
                showChannelView: $showChannelView,
                showPlaylistSearch: $showPlaylistSearch,
                selectedPlaylist: $selectedPlaylist,
                showPlaylistView: $showPlaylistView,
                showUserChannelInput: $showUserChannelInput,
                userChannelURL: $userChannelURL,
                youtubeAPI: youtubeAPI,
                // EN: Resume time for current overlay video. TR: Mevcut panel videosu için devam süresi.
                resumeSeconds: $pendingResumeTime,
                // EN: Optional context for overlay playlist mode. TR: Kaplama playlist modu için isteğe bağlı bağlam.
                overlayPlaylistContext: $overlayPlaylistContext,
                // EN: Show top tab strip globally on this page. TR: Bu sayfada üst sekme şeridini global göster.
                showTabStrip: true,
                // EN: Toggle bottom audio bar visibility. TR: Alt ses çubuğu görünürlüğü.
                showBottomPlayerBar: $showBottomPlayerBar
            )
            // EN: Inject audio player into content area. TR: İçerik alanına ses oynatıcıyı enjekte et.
            .environmentObject(audioPlayer)
    }
        // EN: Provide audio player globally (including sidebar). TR: Ses oynatıcıyı global sağla (sidebar dahil).
        .environmentObject(audioPlayer)
        // EN: Native toolbar with search and quick actions. TR: Arama ve hızlı eylemler içeren yerel araç çubuğu.
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // EN: Slightly smaller fixed-width search field. TR: Biraz daha küçük sabit genişlikte arama alanı.
                ToolbarSearchField(text: $searchText, placeholder: i18n.t(.searchPlaceholder) + "...", width: 220) {
                    // EN: On submit: close overlays if needed, maybe redirect, then search. TR: Gönderimde: gerekiyorsa kaplamaları kapat, gerekirse yönlendir, sonra ara.
                    if !searchText.isEmpty {
                        // EN: Close open video panel if any. TR: Açık video paneli varsa kapat.
                        if selectedVideo != nil {
                            withAnimation(.easeInOut) { selectedVideo = nil }
                        }
                        // EN: Close channel sheet for a cleaner search-focused layout. TR: Arama odaklı sade görünüm için kanal panelini kapat.
                        if showChannelSheet {
                            withAnimation(.easeInOut) {
                                showChannelSheet = false
                                selectedChannel = nil
                                youtubeAPI.channelInfo = nil
                            }
                        }
                        // EN: If searching from Shorts/Subscriptions/Playlists/History, redirect to Home so search layout shows. TR: Shorts/Abonelikler/Playlist/Geçmişten ararken Home'a dön ki arama düzeni görünsün.
                        let redirectPages: Set<String> = [
                            "https://www.youtube.com/shorts",
                            "https://www.youtube.com/feed/subscriptions",
                            "https://www.youtube.com/feed/playlists",
                            "https://www.youtube.com/feed/history"
                        ]
                        if redirectPages.contains(selectedSidebarId) {
                            withAnimation(.easeInOut) {
                                selectedSidebarId = "https://www.youtube.com/" // Home
                                // EN: Clean Shorts-only UI state if we were actually on Shorts. TR: Shorts sayfasındaysak yalnız Shorts durumunu temizle.
                                if redirectPages.contains("https://www.youtube.com/shorts") { // Only clean Shorts state if we were on Shorts
                                    if selectedSidebarId == "https://www.youtube.com/shorts" {
                                        showShortsComments = false
                                        currentShortsIndex = 0
                                    }
                                }
                            }
                        }
                        // EN: Trigger video search via service. TR: Servis üzerinden video aramasını tetikle.
                        youtubeAPI.searchVideos(query: searchText)
                    }
                }

                // EN: Quick open: channel search sheet. TR: Hızlı aç: kanal arama paneli.
                Button(action: { showChannelSearch = true }) {
                    Image(systemName: "at.circle")
                        .font(.system(size: 18))
                        .symbolRenderingMode(.monochrome)
                }
                .help(i18n.t(.searchChannel))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)

                // EN: Quick open: playlist search sheet. TR: Hızlı aç: oynatma listesi arama paneli.
                Button(action: { showPlaylistSearch = true }) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 18))
                        .symbolRenderingMode(.monochrome)
                }
                .help(i18n.t(.searchPlaylist))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)

                // EN: Global close button when a video or channel overlay is open. TR: Video veya kanal kaplaması açıkken global kapatma düğmesi.
                if selectedVideo != nil || showChannelSheet {
                    Button(action: {
                        withAnimation(.easeInOut) {
                            if selectedVideo != nil { selectedVideo = nil }
                            if showChannelSheet {
                                showChannelSheet = false
                                // Kanal paneli kapatıldığında, eğer Sidebar seçimimiz bir kanal id'si ise Home'a dön
                                if youtubeAPI.userSubscriptionsFromURL.contains(where: { $0.id == selectedSidebarId }) {
                                    selectedSidebarId = "https://www.youtube.com/"
                                }
                            }
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18, weight: .regular))
                            .symbolRenderingMode(.monochrome)
                    }
                    .help(i18n.t(.closePanelHint))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
                }
            }
        }
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty {
                // EN: On clear: exit search mode and restore previous content. TR: Temizlenince: arama modundan çık, önceki içeriği geri getir.
                if youtubeAPI.isShowingSearchResults {
                    if selectedSidebarId == "https://www.youtube.com/" {
                        if let id = youtubeAPI.selectedCustomCategoryId, let custom = youtubeAPI.customCategories.first(where: { $0.id == id }) {
                            youtubeAPI.fetchVideos(for: custom, suppressOverlay: true)
                        } else {
                            youtubeAPI.fetchHomeRecommendations(suppressOverlay: true)
                        }
                    }
                    // EN: Rebuild Shorts rail out of search context. TR: Shorts şeridini arama bağlamından çıkarıp yeniden oluştur.
                    youtubeAPI.fetchShortsVideos(suppressOverlay: true)
                    youtubeAPI.currentSearchQuery = ""
                    youtubeAPI.isShowingSearchResults = false
                }
            }
        }
        // EN: Close overlays on core page switches; open channel on channel-row selection. TR: Çekirdek sayfa değişiminde kaplamaları kapat; kanal seçilince kanalı aç.
    .onChange(of: selectedSidebarId) { _, newValue in
            // Çekirdek sayfalar (kanal dışı navigation)
            let corePages: Set<String> = [
                "https://www.youtube.com/",
                "https://www.youtube.com/shorts",
                "https://www.youtube.com/feed/subscriptions",
                "https://www.youtube.com/feed/playlists",
                "https://www.youtube.com/feed/history"
            ]

            if corePages.contains(newValue) {
                var didCloseSomething = false
                if selectedVideo != nil {
                    withAnimation(.easeInOut) { selectedVideo = nil }
                    didCloseSomething = true
                }
                if showChannelSheet {
                    withAnimation(.easeInOut) {
                        showChannelSheet = false
                        selectedChannel = nil
                        youtubeAPI.channelInfo = nil
                    }
                    didCloseSomething = true
                }
                if didCloseSomething { print("🔻 Sidebar değişti: Açık panel(ler) kapatıldı") }
            } else {
                // EN: Channel row selected in the native list; open channel sheet. TR: Yerel listede kanal satırı seçildi; kanal panelini aç.
                if let channel = youtubeAPI.userSubscriptionsFromURL.first(where: { $0.id == newValue }) {
                    // Yeni bir kanal ya da kanal paneli kapalı ise aç
                    if selectedChannel?.id != channel.id || !showChannelSheet {
                        selectedChannel = channel
                        withAnimation(.easeInOut) { showChannelSheet = true }
                        print("📺 Kanal seçildi: \(channel.title)")
                    }
                }
            }
        }
    .onAppear {
            // EN: App launched: load subs and trigger one-time initial content. TR: Uygulama açıldı: abonelikleri yükle ve tek seferlik içeriği tetikle.
            print("🚀 Uygulama açıldı - initial home load orchestration")
            youtubeAPI.loadSubscriptionsFromUserDefaults()
            youtubeAPI.performInitialHomeLoadIfNeeded()
            // EN: When PiP closes: if panel is closed, open/focus a tab; pass resume time. TR: PiP kapanınca: panel kapalıysa sekme aç/odakla; devam süresini aktar.
            NotificationCenter.default.addObserver(forName: .miniPlayerClosed, object: nil, queue: .main) { note in
                guard let vId = note.userInfo?["videoId"] as? String else { return }
                let time = note.userInfo?["time"] as? Double
                guard let video = youtubeAPI.findVideo(by: vId) else { return }

                // EN: If inline panel is closed, open/focus a tab (preserve prior panel behavior otherwise). TR: Panel kapalıysa sekme aç/odakla (aksi halde mevcut panel davranışını koru).
                if selectedVideo == nil {
                    Task { @MainActor in
                        // Sekme mevcutsa odakla, yoksa oluştur ve odakla
                        if let idx = tabs.indexOfTab(forVideoId: vId) {
                            tabs.activeTabId = tabs.tabs[idx].id
                        } else {
                            tabs.openOrActivate(videoId: vId, title: video.title, isShorts: false)
                        }
                        // Zaman bilgisi varsa, içeriğin yüklenmesi için küçük bir gecikme ile ilet
                        if let t = time {
                            try? await Task.sleep(nanoseconds: 300_000_000)
                            NotificationCenter.default.post(name: .seekToSeconds, object: nil, userInfo: ["seconds": Int(t)])
                        }
                    }
                    return
                }

                // EN: If panel is open, reopen/seek within the panel. TR: Panel açıksa panel içinde yeniden aç/ara.
                var changed = false
                if showChannelSheet { showChannelSheet = false; selectedChannel = nil; changed = true }
                if selectedVideo?.id != video.id {
                    pendingResumeTime = time
                    selectedVideo = video
                    changed = true
                } else if let t = time {
                    NotificationCenter.default.post(name: .seekToSeconds, object: nil, userInfo: ["seconds": Int(t)])
                }
                if changed { print("🔁 PiP kapandı, video paneli yeniden açıldı: \(video.title)") }
            }
            // EN: Go Home: reset to default home page and close overlays/tabs. TR: Ana Sayfa: varsayılan ana sayfaya dön ve kaplamaları/sekmeleri kapat.
            NotificationCenter.default.addObserver(forName: .goHome, object: nil, queue: .main) { _ in
                // Ensure all UI and TabCoordinator mutations run on the MainActor (Swift 5 app target)
                Task {
                    await MainActor.run {
                        withAnimation(.easeInOut) {
                            // Default home page
                            selectedSidebarId = "https://www.youtube.com/"
                            // Exit from any active tab content
                            tabs.activeTabId = nil
                            // Close overlays so home is visible
                            if selectedVideo != nil { selectedVideo = nil }
                            if showChannelSheet { showChannelSheet = false; selectedChannel = nil }
                        }
                    }
                }
            }
            // EN: Playlist mode (tab): open a specific/first video in a new or active tab. TR: Playlist modu (sekme): belirli/ilk videoyu yeni veya aktif sekmede aç.
            NotificationCenter.default.addObserver(forName: .openPlaylistMode, object: nil, queue: .main) { note in
                guard let pid = note.userInfo?["playlistId"] as? String else { return }
                let desiredId = note.userInfo?["videoId"] as? String
                let desiredIndex = note.userInfo?["index"] as? Int
                Task { @MainActor in
                    if let p = (youtubeAPI.userPlaylists.first(where: { $0.id == pid }) ?? youtubeAPI.searchedPlaylists.first(where: { $0.id == pid })) {
                        await youtubeAPI.ensurePlaylistLoadedCount(playlist: p, minCount: 1)
                        let ctx = PlaylistContext(playlistId: pid)
                        if let vid = desiredId, !vid.isEmpty {
                            if let v = youtubeAPI.findVideo(by: vid) {
                                await MainActor.run { tabs.openOrActivate(videoId: v.id, title: v.title, isShorts: false, playlist: ctx) }
                            } else if let cached = youtubeAPI.cachedPlaylistVideos[pid]?.first(where: { $0.id == vid }), !cached.title.isEmpty {
                                await MainActor.run { tabs.openOrActivate(videoId: vid, title: cached.title, isShorts: false, playlist: ctx) }
                            } else {
                                await MainActor.run { tabs.openOrActivate(videoId: vid, title: "Video", isShorts: false, playlist: ctx) }
                            }
                            NotificationCenter.default.post(name: .openPlaylistVideo, object: nil, userInfo: ["playlistId": pid, "videoId": vid, "index": desiredIndex ?? 0])
                        } else {
                            let first = youtubeAPI.cachedPlaylistVideos[pid]?.first
                            guard let start = first?.id, !start.isEmpty else { return }
                            await MainActor.run { tabs.openOrActivate(videoId: start, title: first?.title ?? "Video", isShorts: false, playlist: ctx) }
                            NotificationCenter.default.post(name: .openPlaylistVideo, object: nil, userInfo: ["playlistId": pid, "videoId": start, "index": 0])
                        }
                    }
                }
            }
            // EN: Overlay playlist mode: open a specific video inside the inline panel. TR: Kaplama playlist modu: belirli videoyu satır içi panelde aç.
            NotificationCenter.default.addObserver(forName: .openPlaylistModeOverlay, object: nil, queue: .main) { note in
                guard let pid = note.userInfo?["playlistId"] as? String else { return }
                let desiredId = note.userInfo?["videoId"] as? String
                let desiredIndex = note.userInfo?["index"] as? Int
                Task { @MainActor in
                    if let p = (youtubeAPI.userPlaylists.first(where: { $0.id == pid }) ?? youtubeAPI.searchedPlaylists.first(where: { $0.id == pid })) {
                        await youtubeAPI.ensurePlaylistLoadedCount(playlist: p, minCount: 1)
                        let ctx = PlaylistContext(playlistId: pid)
                        // Ensure overlay context is set to this playlist
                        withAnimation(.easeInOut) { overlayPlaylistContext = ctx }
                        if let vid = desiredId, !vid.isEmpty {
                            if let v = youtubeAPI.findVideo(by: vid) {
                                withAnimation(.easeInOut) { selectedVideo = v }
                            } else {
                                withAnimation(.easeInOut) {
                                    selectedVideo = YouTubeVideo.makePlaceholder(id: vid)
                                }
                            }
                            NotificationCenter.default.post(name: .openPlaylistVideo, object: nil, userInfo: ["playlistId": pid, "videoId": desiredId!, "index": desiredIndex ?? 0])
                        } else if let first = youtubeAPI.cachedPlaylistVideos[pid]?.first, !first.id.isEmpty {
                            withAnimation(.easeInOut) { selectedVideo = first }
                            NotificationCenter.default.post(name: .openPlaylistVideo, object: nil, userInfo: ["playlistId": pid, "videoId": first.id, "index": 0])
                        }
                    }
                }
            }
        // EN: Open a specific video inside playlist mode (panel rows). TR: Playlist modu içinde belirli bir videoyu aç (panel satırları).
            NotificationCenter.default.addObserver(forName: .openPlaylistVideo, object: nil, queue: .main) { note in
                guard let pid = note.userInfo?["playlistId"] as? String,
                      let vid = note.userInfo?["videoId"] as? String else { return }
                let ctx = PlaylistContext(playlistId: pid)
                // If overlay playlist mode is active, replace inline panel video; otherwise use tabs flow
                if overlayPlaylistContext?.playlistId == pid, selectedVideo != nil {
                    if let v = youtubeAPI.findVideo(by: vid) { withAnimation(.easeInOut) { selectedVideo = v } }
                    else { withAnimation(.easeInOut) { selectedVideo = YouTubeVideo.makePlaceholder(id: vid) } }
                } else {
                    Task { @MainActor in
                        if let v = youtubeAPI.findVideo(by: vid) {
                            await MainActor.run { tabs.openOrActivate(videoId: v.id, title: v.title, isShorts: false, playlist: ctx) }
                        } else if let cached = youtubeAPI.cachedPlaylistVideos[pid]?.first(where: { $0.id == vid }), !cached.title.isEmpty {
                            await MainActor.run { tabs.openOrActivate(videoId: vid, title: cached.title, isShorts: false, playlist: ctx) }
                        } else {
                            await MainActor.run { tabs.openOrActivate(videoId: vid, title: "Video", isShorts: false, playlist: ctx) }
                        }
                    }
                }
            }
            // EN: Bottom mini player bar show/hide. TR: Alt mini oynatıcı çubuğunu göster/gizle.
            NotificationCenter.default.addObserver(forName: .showBottomPlayerBar, object: nil, queue: .main) { _ in
                withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) { showBottomPlayerBar = true }
            }
            NotificationCenter.default.addObserver(forName: .hideBottomPlayerBar, object: nil, queue: .main) { _ in
                withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) { showBottomPlayerBar = false }
            }
            // EN: Start audio-only playlist playback. TR: Yalnız ses playlist oynatımını başlat.
            NotificationCenter.default.addObserver(forName: .startAudioPlaylist, object: nil, queue: .main) { note in
                guard let pid = note.userInfo?["playlistId"] as? String else { return }
                let index = note.userInfo?["index"] as? Int
                Task { @MainActor in
                    // If playlist not in user list yet but exists in search results, make sure at least 1 item is loaded
                    if youtubeAPI.cachedPlaylistVideos[pid]?.isEmpty ?? true,
                       let p = (youtubeAPI.userPlaylists.first(where: { $0.id == pid }) ?? youtubeAPI.searchedPlaylists.first(where: { $0.id == pid })) {
                        await youtubeAPI.ensurePlaylistLoadedCount(playlist: p, minCount: 1)
                    }
                    audioPlayer.start(playlistId: pid, startIndex: index, using: youtubeAPI)
                }
            }

            // EN: Open a normal video overlay (from mini player Video button). TR: Normal video kaplaması aç (mini oynatıcı Video butonundan).
            NotificationCenter.default.addObserver(forName: .openVideoOverlay, object: nil, queue: .main) { note in
                guard let vId = note.userInfo?["videoId"] as? String else { return }
                let time = note.userInfo?["time"] as? Double
                let pid = note.userInfo?["playlistId"] as? String
                // Map optional playlistId to overlay context if the video belongs to it
                var ctx: PlaylistContext? = nil
                if let pid, !pid.isEmpty {
                    ctx = PlaylistContext(playlistId: pid)
                }
                // Open overlay panel with optional resume time
                if let v = youtubeAPI.findVideo(by: vId) {
                    withAnimation(.easeInOut) {
                        overlayPlaylistContext = ctx
                        pendingResumeTime = time
                        selectedVideo = v
                        // Ensure bottom mini bar is hidden
                        showBottomPlayerBar = false
                    }
                } else {
                    withAnimation(.easeInOut) {
                        overlayPlaylistContext = ctx
                        pendingResumeTime = time
                        selectedVideo = YouTubeVideo.makePlaceholder(id: vId)
                        showBottomPlayerBar = false
                    }
                }
            }
        }
        // EN: When playlist overlay is active, refresh selected panel video as items enrich. TR: Kaplama playlist aktifken, öğeler zenginleştikçe paneldeki seçili videoyu tazele.
        .onReceive(youtubeAPI.$cachedPlaylistVideos) { _ in
            // Yalnızca overlay playlist modu aktifken ve panelde bir video varken çalıştır
            guard let ctx = overlayPlaylistContext, let current = selectedVideo else { return }
            // Aynı id'li güncel kopyayı playlist cache'inden al
            if let updated = youtubeAPI.cachedPlaylistVideos[ctx.playlistId]?.first(where: { $0.id == current.id }) {
                // Görünür alanlarda değişiklik olduysa reassignment yap (SwiftUI yeniden çizsin)
                if updated.viewCount != current.viewCount || updated.publishedAt != current.publishedAt || updated.title != current.title || updated.description != current.description || updated.durationText != current.durationText {
                    withAnimation(.easeInOut(duration: 0.15)) { selectedVideo = updated }
                }
            }
        }
    }
    
    // Native Apple Sidebar - Finder tarzı
    private var nativeSidebar: some View {
        // EN: Finder-like sidebar with core pages and subscriptions. TR: Çekirdek sayfalar ve aboneliklerle Finder benzeri yan menü.
        VStack(spacing: 0) {
        List(selection: $selectedSidebarId) {
        // EN: Core pages section. TR: Çekirdek sayfalar bölümü.
        Section(i18n.t(.you)) {
                   NavigationLink(value: "https://www.youtube.com/") {
            Label(i18n.t(.home), systemImage: "house")
                }
                .tag("https://www.youtube.com/")
                
                NavigationLink(value: "https://www.youtube.com/shorts") {
                    Label(i18n.t(.shorts), systemImage: "play.rectangle.on.rectangle")
                }
                .tag("https://www.youtube.com/shorts")
                
                NavigationLink(value: "https://www.youtube.com/feed/subscriptions") {
                    Label(i18n.t(.subscriptions), systemImage: "person.2")
                }
                .tag("https://www.youtube.com/feed/subscriptions")
                // Playlists entry
                NavigationLink(value: "https://www.youtube.com/feed/playlists") {
                    Label(i18n.t(.playlists), systemImage: "music.note.list")
                }
                .tag("https://www.youtube.com/feed/playlists")
                NavigationLink(value: "https://www.youtube.com/feed/history") {
                    Label(i18n.t(.history), systemImage: "clock")
                }
                .tag("https://www.youtube.com/feed/history")
                
                // EN: Manual channel add flow. TR: Elle kanal ekleme akışı.
                Button(action: {
                    showUserChannelInput = true
                }) {
                    Label(i18n.t(.addChannel), systemImage: "plus.circle")
                }
                .foregroundColor(.primary)
            }
            // EN: Subscriptions list section. TR: Abonelikler bölümü.
            if !youtubeAPI.userSubscriptionsFromURL.isEmpty {
                Section(i18n.t(.subscriptionsSection)) {
                    ForEach(youtubeAPI.userSubscriptionsFromURL, id: \.id) { channel in
                        HStack {
                            // EN: Channel avatar. TR: Kanal avatarı.
                            AsyncImage(url: URL(string: channel.thumbnailURL)) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                            }
                            .frame(width: 24, height: 24)
                            .clipShape(Circle())

                            // EN: Channel title. TR: Kanal başlığı.
                            Text(channel.title)
                                .foregroundColor(.primary)
                                .lineLimit(1)

                            Spacer()
                        }
                        .tag(channel.id) // EN: Native selection highlight & full-row clickability. TR: Yerel seçim vurgusu ve tam satır tıklanabilirlik.
                        .contentShape(Rectangle())
                    }
                }
            }
        }
            // Sidebar bottom: Now Playing (audio-only)
            // EN: Compact now playing card for audio-only mode. TR: Yalnız ses modu için küçük şimdi çalan kartı.
            if audioPlayer.isActive, let v = audioPlayer.currentVideo {
                Divider()
                    .overlay(Color.primary.opacity(0.08))
                VStack(alignment: .leading, spacing: 8) {
                    // Thumbnail on top
                    // Compute thumbnail URL from id to avoid stale/missing thumbnailURL in cached playlist items
                    let thumbURL = URL(string: youtubeThumbnailURL(v.id, quality: .hqdefault))
                    if let url = thumbURL {
                        AsyncImage(url: url) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Rectangle().fill(Color.secondary.opacity(0.2))
                        }
                        .id(v.id) // ensure refresh when track changes
                        .frame(height: 96)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // Title
                    Text(v.title.isEmpty ? i18n.t(.video) : v.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    // Channel
                    if !v.channelTitle.isEmpty {
                        Text(v.channelTitle)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(10)
            }
        }
        .frame(minWidth: 200)
    }
    
    // Native Main Content
    private var nativeMainContent: some View {
    // EN: Layer page content with overlays and top-aligned controls. TR: Sayfa içeriğini kaplamalar ve üst hizalı kontrollerle katmanlandır.
    ZStack(alignment: .top) {
            // Asıl içerik (bar gösterildiğinde üstten padding veriyoruz)
            Group {
                if selectedSidebarId == "https://www.youtube.com/feed/subscriptions" {
                    // EN: Subscriptions page. TR: Abonelikler sayfası.
                    SubscriptionsView(youtubeAPI: youtubeAPI)
                } else if selectedSidebarId == "https://www.youtube.com/feed/history" {
                    // EN: Watch history view. TR: İzleme geçmişi görünümü.
                    WatchHistoryView(
                        youtubeAPI: youtubeAPI,
                        selectedChannel: $selectedChannel,
                        showChannelSheet: $showChannelSheet,
                        selectedVideo: $selectedVideo
                    )
                } else if selectedSidebarId == "https://www.youtube.com/shorts" {
                    // EN: Shorts page. TR: Shorts sayfası.
                    ShortsView(
                        youtubeAPI: youtubeAPI,
                        showShortsComments: $showShortsComments,
                        currentShortsIndex: $currentShortsIndex
                    )
                } else if selectedSidebarId == "https://www.youtube.com/feed/playlists" {
                    // EN: Playlists page. TR: Playlist'ler sayfası.
                    PlaylistSearchView(
                        youtubeAPI: youtubeAPI,
                        selectedPlaylist: $selectedPlaylist,
                        showPlaylistView: $showPlaylistView,
                        showHeader: false
                    )
                } else {
                    // EN: Home page. TR: Ana sayfa.
                    HomePageView(
                        youtubeAPI: youtubeAPI,
                        selectedChannel: $selectedChannel,
                        showChannelSheet: $showChannelSheet,
                        selectedVideo: $selectedVideo,
                        selectedSidebarId: $selectedSidebarId,
                        currentURL: $currentURL,
                        currentShortsIndex: $currentShortsIndex
                    )
                }

                // EN: Global loading overlay (hidden when Shorts list loaded). TR: Global yükleme katmanı (Shorts listesi geldiğinde gizle).
                if youtubeAPI.showGlobalLoading && (selectedSidebarId != "https://www.youtube.com/shorts" || youtubeAPI.shortsVideos.isEmpty) {
                    LoadingOverlayView()
                }
                if let error = youtubeAPI.error { ErrorOverlayView(error: error) }
            }
            .onAppear {
                // EN: On appear: rely on initial load gate if not in search mode (no extra calls). TR: Göründüğünde: arama modunda değilsek ilk yükleme kapısına güven (ekstra çağrı yok).
                guard !youtubeAPI.isShowingSearchResults else { return }
                print("📺 MainContentView onAppear (content) — relying on initialHomeLoad gate")
                youtubeAPI.performInitialHomeLoadIfNeeded()
            }
            // EN: Region change notice (actual refresh handled in service). TR: Bölge değişim uyarısı (gerçek yenileme serviste).
            .onReceive(NotificationCenter.default.publisher(for: .selectedRegionChanged)) { _ in
                // Region change already triggers refreshes inside YouTubeAPIService.didSet.
                // Avoid duplicating fetches here to prevent visible double-refresh.
                print("🌐 Region changed (view): refresh handled by service")
            }
            
            VStack(spacing: 0) {
                // EN: Category Bar at top: only on Home when no overlays. TR: Üstte Kategori Çubuğu: yalnız Ana sayfada ve kaplama yokken.
                let isHome = (selectedSidebarId == "https://www.youtube.com/")
                let noOverlay = (selectedVideo == nil && !showChannelSheet)
                if !youtubeAPI.isShowingSearchResults && isHome && noOverlay {
                    CategoryBarView(youtubeAPI: youtubeAPI, selectedSidebarId: selectedSidebarId)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                Spacer(minLength: 0)
                // EN: Hidden audio host to keep the webview alive. TR: WebView'i canlı tutmak için gizli ses host'u.
                HiddenAudioPlayerView(audio: audioPlayer)
                    .frame(width: 1, height: 1)
                    .opacity(0.0)
            }
            .frame(maxWidth: .infinity, alignment: .top)

            // EN: Active tab content overlays the main page (video panel area). TR: Aktif sekme içeriği ana sayfanın üzerinde (video panel alanı).
            TabHostView(tabs: tabs, youtubeAPI: youtubeAPI)
        }
    .frame(minWidth: 800, minHeight: 600)
    // EN: TabStripView is shown globally from SheetManagementView. TR: TabStripView global olarak SheetManagementView'den gösterilir.
    }
}

// MARK: - AppKit-backed NSSearchField for toolbar sizing / Araç çubuğu boyutu için AppKit NSSearchField
struct ToolbarSearchField: NSViewRepresentable {
    // EN: Two-way binding for field text. TR: Alan metni için çift yönlü bağ.
    @Binding var text: String
    // EN: Placeholder text. TR: Yer tutucu metin.
    var placeholder: String
    // EN: Fixed width for consistent toolbar layout. TR: Tutarlı araç çubuğu düzeni için sabit genişlik.
    var width: CGFloat = 220
    // EN: Callback when user submits (Enter/search icon). TR: Kullanıcı gönderdiğinde geri çağırım (Enter/arama ikonu).
    var onSubmit: () -> Void

    // EN: Create and configure NSSearchField. TR: NSSearchField oluştur ve yapılandır.
    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = placeholder
        field.controlSize = .small
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.didSubmit(_:))
        // Only trigger action when user explicitly submits (Enter or search icon)
        if let cell = field.cell as? NSSearchFieldCell {
            // Prevent incremental searches while typing
            cell.sendsSearchStringImmediately = false
            cell.sendsWholeSearchString = true
            // Ensure single-line horizontal scrolling instead of clipping long text
            cell.wraps = false
            cell.isScrollable = true
        }
        // Additional safeguard for single-line mode
        field.usesSingleLineMode = true
        field.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            field.widthAnchor.constraint(equalToConstant: width)
        ])
        return field
    }

    // EN: Keep AppKit view in sync with SwiftUI state. TR: AppKit görünümünü SwiftUI durumu ile senkron tut.
    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    // EN: Create coordinator to bridge delegate/callbacks. TR: Temsilci/geri çağrılar için köprü koordinatörü oluştur.
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: ToolbarSearchField
        init(_ parent: ToolbarSearchField) { self.parent = parent }

        // EN: Update binding on each text change and keep caret visible. TR: Her metin değişiminde bağı güncelle ve imleci görünür tut.
        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSearchField else { return }
            parent.text = field.stringValue
            // Manually keep caret (insertion point) visible when content exceeds width.
            if let editor = field.currentEditor() as? NSTextView, !editor.hasMarkedText() {
                let end = editor.string.count
                // Don't alter selection if user moved caret manually away from end
                if editor.selectedRange.location >= end - 1 { // typing at end
                    editor.scrollRangeToVisible(NSRange(location: end, length: 0))
                }
            }
        }

        // EN: Treat Enter/search as submit. TR: Enter/arama eylemini gönderim say.
        @objc func didSubmit(_ sender: Any?) {
            parent.onSubmit()
        }

        // EN: Intercept Enter key to trigger submit. TR: Enter tuşunu yakalayıp gönderimi tetikle.
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }
    }
}

#Preview {
    // EN: Preview of the primary content container. TR: Birincil içerik konteynerinin önizlemesi.
    MainContentView()
}
