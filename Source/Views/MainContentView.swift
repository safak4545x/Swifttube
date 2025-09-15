
/*
 File Overview (EN)
 Purpose: Primary container of the app UI. Hosts the native macOS sidebar, the main content area, search toolbar, overlays (video panel, tabs), and global loading/error overlays.
 Key Responsibilities:
 - Manage navigation between Home, Shorts, Subscriptions, Playlists, and History via native Sidebar
 - Orchestrate overlays: inline video panel, TabHostView, bottom audio player bar
 - Provide toolbar search integrated with YouTubeAPIService
 - React to app-wide notifications (PiP close, goHome, playlist open, bottom bar show/hide)
 Used By: App window content inside SwifttubeApp's WindowGroup.

 Dosya Özeti (TR)
 Amacı: Uygulamanın ana UI konteyneri. Yerel macOS yan menüsünü, ana içerik alanını, arama araç çubuğunu, katmanlı panelleri (video paneli, sekmeler) ve global yükleme/hata katmanlarını barındırır.
 Ana Sorumluluklar:
 - Yerel Sidebar ile Ana Sayfa, Shorts, Abonelikler, Çalma Listeleri ve Geçmiş arasında gezinmeyi yönetmek
 - Katmanları orkestre etmek: satır içi video paneli, TabHostView, alt ses oynatıcı çubuğu
 - YouTubeAPIService ile entegre arama araç çubuğu sağlamak
 - Uygulama genel bildirimlerine tepki vermek (PiP kapanışı, ana sayfaya dön, playlist aç, alt çubuğu göster/gizle)
 Nerede Kullanılır: SwifttubeApp içindeki WindowGroup kapsamında ana içerik olarak.
*/

import SwiftUI
import AppKit

struct MainContentView: View {
    @EnvironmentObject var i18n: Localizer
    @EnvironmentObject private var tabs: TabCoordinator
    @State private var selectedChannel: YouTubeChannel? = nil
    @State private var showChannelSheet: Bool = false
    @State private var selectedSidebarId: String = sidebarItems.first!.id
    @State private var currentURL: String = sidebarItems.first!.url
    @State private var searchText: String = ""
    @State private var selectedVideo: YouTubeVideo? = nil
    // PiP dönüşünde kaldığı yerden devam için saniye
    @State private var pendingResumeTime: Double? = nil
    @State private var showShortsComments = false
    @State private var currentShortsIndex = 0
    @StateObject private var youtubeAPI = YouTubeAPIService()
    @StateObject private var sidebarState = SidebarState()
        @StateObject private var audioPlayer = AudioPlaylistPlayer()

    // Persisted playlist mode state: last selected video per playlist
    @State private var playlistModeSelectedVideoId: String? = nil
    // Overlay (non-tab) playlist context when opening via left-click on Play
    @State private var overlayPlaylistContext: PlaylistContext? = nil

    // Search States
    @State private var showChannelSearch = false
    @State private var showPlaylistSearch = false
    @State private var selectedPlaylist: YouTubePlaylist? = nil
    @State private var showChannelView = false
    @State private var showPlaylistView = false
    // Bottom player placeholder visibility
    @State private var showBottomPlayerBar: Bool = false
    
    // User Channel URL Input
    @State private var showUserChannelInput = false
    @State private var userChannelURL = ""

    var body: some View {
    NavigationSplitView {
            // Native Apple Sidebar
            nativeSidebar
        } detail: {
            // Main Content
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
                resumeSeconds: $pendingResumeTime,
                overlayPlaylistContext: $overlayPlaylistContext,
                showTabStrip: true,
                showBottomPlayerBar: $showBottomPlayerBar
            )
            .environmentObject(audioPlayer)
    }
        .environmentObject(audioPlayer)
        // Use native search field in the toolbar
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Slightly smaller search field (fixed width)
                ToolbarSearchField(text: $searchText, placeholder: i18n.t(.searchPlaceholder) + "...", width: 220) {
                    if !searchText.isEmpty {
                        // Arama yapıldığında açık video panelini kapat
                        if selectedVideo != nil {
                            withAnimation(.easeInOut) { selectedVideo = nil }
                        }
                        // Açık kanal sheet'i varsa kapat (arama odaklı sade görünüm)
                        if showChannelSheet {
                            withAnimation(.easeInOut) {
                                showChannelSheet = false
                                selectedChannel = nil
                                youtubeAPI.channelInfo = nil
                            }
                        }
                        // Shorts / Abonelikler / Geçmiş sayfalarından arama yapılırsa Home'a dön ki arama sonuçları layout'u görünsün
                        let redirectPages: Set<String> = [
                            "https://www.youtube.com/shorts",
                            "https://www.youtube.com/feed/subscriptions",
                            "https://www.youtube.com/feed/playlists",
                            "https://www.youtube.com/feed/history"
                        ]
                        if redirectPages.contains(selectedSidebarId) {
                            withAnimation(.easeInOut) {
                                selectedSidebarId = "https://www.youtube.com/" // Home
                                if redirectPages.contains("https://www.youtube.com/shorts") { // Only clean Shorts state if we were on Shorts
                                    if selectedSidebarId == "https://www.youtube.com/shorts" {
                                        showShortsComments = false
                                        currentShortsIndex = 0
                                    }
                                }
                            }
                        }
                        youtubeAPI.searchVideos(query: searchText)
                    }
                }

                // Bigger buttons with subdued tint matching search field
                Button(action: { showChannelSearch = true }) {
                    Image(systemName: "at.circle")
                        .font(.system(size: 18))
                        .symbolRenderingMode(.monochrome)
                }
                .help(i18n.t(.searchChannel))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)

                Button(action: { showPlaylistSearch = true }) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 18))
                        .symbolRenderingMode(.monochrome)
                }
                .help(i18n.t(.searchPlaylist))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)

                // Herhangi bir overlay (video veya kanal) açıksa kapatma butonu
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
                // Arama kutusu temizlenince: mevcut arama modundan çık ve önceki kategori videolarını geri getir.
                if youtubeAPI.isShowingSearchResults {
                    if selectedSidebarId == "https://www.youtube.com/" {
                        if let id = youtubeAPI.selectedCustomCategoryId, let custom = youtubeAPI.customCategories.first(where: { $0.id == id }) {
                            youtubeAPI.fetchVideos(for: custom, suppressOverlay: true)
                        } else {
                            youtubeAPI.fetchHomeRecommendations(suppressOverlay: true)
                        }
                    }
                    // Shorts listesini de arama sonuçlarından çıkarıp yeniden rastgele oluştur.
                    youtubeAPI.fetchShortsVideos(suppressOverlay: true)
                    youtubeAPI.currentSearchQuery = ""
                    youtubeAPI.isShowingSearchResults = false
                }
            }
        }
        // Sidebar'da sayfa değiştiğinde açık video panelini kapat
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
                // Kanal satırı seçildi (native List selection). Kanalı aç.
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
            // Uygulama açıldı: abonelikleri yükle ve tek seferlik başlangıç içeriğini servis üzerinden getir
            print("🚀 Uygulama açıldı - initial home load orchestration")
            youtubeAPI.loadSubscriptionsFromUserDefaults()
            youtubeAPI.performInitialHomeLoadIfNeeded()
            // Mini (PiP) kapandığında: panel kapalıysa sekmede aç/odakla; zaman bilgisini aktar
            NotificationCenter.default.addObserver(forName: .miniPlayerClosed, object: nil, queue: .main) { note in
                guard let vId = note.userInfo?["videoId"] as? String else { return }
                let time = note.userInfo?["time"] as? Double
                guard let video = youtubeAPI.findVideo(by: vId) else { return }

                // Eğer inline video paneli açık ise eski davranış: aynı panelde devam (mevcut kod yukarıda)
                // Biz burada panel kapalıyken sekme açılmasını sağlıyoruz
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

                // Panel açık ise mevcut davranışı koru (panelde aç)
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
            // Playlist mode opener: open a specific video in a new/active tab (middle click), or the first if none provided
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
            // Overlay playlist mode opener: open a specific video inside inline Video Panel on the page (left click)
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
            // Open specific video inside playlist mode (from the playlist panel rows)
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
            // Bottom player bar toggles
            NotificationCenter.default.addObserver(forName: .showBottomPlayerBar, object: nil, queue: .main) { _ in
                withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) { showBottomPlayerBar = true }
            }
            NotificationCenter.default.addObserver(forName: .hideBottomPlayerBar, object: nil, queue: .main) { _ in
                withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) { showBottomPlayerBar = false }
            }
            // Start audio-only playlist playback
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

            // Open normal video overlay on top of the page (from mini player Video button)
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
        // Playlist overlay aktifken, playlist içerikleri zenginleşip güncellenince paneldeki seçili videoyu tazele
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
        VStack(spacing: 0) {
        List(selection: $selectedSidebarId) {
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
                
                Button(action: {
                    showUserChannelInput = true
                }) {
                    Label(i18n.t(.addChannel), systemImage: "plus.circle")
                }
                .foregroundColor(.primary)
            }
            // Abonelikler listesi
            if !youtubeAPI.userSubscriptionsFromURL.isEmpty {
                Section(i18n.t(.subscriptionsSection)) {
                    ForEach(youtubeAPI.userSubscriptionsFromURL, id: \.id) { channel in
                        HStack {
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

                            Text(channel.title)
                                .foregroundColor(.primary)
                                .lineLimit(1)

                            Spacer()
                        }
                        .tag(channel.id) // Native selection highlight & tam satır tıklanabilirlik
                        .contentShape(Rectangle())
                    }
                }
            }
        }
            // Sidebar bottom: Now Playing (audio-only)
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
    ZStack(alignment: .top) {
            // Asıl içerik (bar gösterildiğinde üstten padding veriyoruz)
            Group {
                if selectedSidebarId == "https://www.youtube.com/feed/subscriptions" {
                    // Abonelikler sayfası
                    SubscriptionsView(youtubeAPI: youtubeAPI)
                } else if selectedSidebarId == "https://www.youtube.com/feed/history" {
                    // Geçmiş görünümü
                    WatchHistoryView(
                        youtubeAPI: youtubeAPI,
                        selectedChannel: $selectedChannel,
                        showChannelSheet: $showChannelSheet,
                        selectedVideo: $selectedVideo
                    )
                } else if selectedSidebarId == "https://www.youtube.com/shorts" {
                    // Shorts görünümü
                    ShortsView(
                        youtubeAPI: youtubeAPI,
                        showShortsComments: $showShortsComments,
                        currentShortsIndex: $currentShortsIndex
                    )
                } else if selectedSidebarId == "https://www.youtube.com/feed/playlists" {
                    // Playlists sayfası
                    PlaylistSearchView(
                        youtubeAPI: youtubeAPI,
                        selectedPlaylist: $selectedPlaylist,
                        showPlaylistView: $showPlaylistView,
                        showHeader: false
                    )
                } else {
                    // Ana sayfa görünümü
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

                // Global loading overlay: Shorts sayfasında videolar listesi geldiyse kapat
                if youtubeAPI.showGlobalLoading && (selectedSidebarId != "https://www.youtube.com/shorts" || youtubeAPI.shortsVideos.isEmpty) {
                    LoadingOverlayView()
                }
                if let error = youtubeAPI.error { ErrorOverlayView(error: error) }
            }
            .onAppear {
                // İçerik alanı görününce: arama modunda değilsek initial load gate'e güven; ekstra çağrı yok
                guard !youtubeAPI.isShowingSearchResults else { return }
                print("📺 MainContentView onAppear (content) — relying on initialHomeLoad gate")
                youtubeAPI.performInitialHomeLoadIfNeeded()
            }
            // Bölge değişince görünümdeki listeyi güncelle
            .onReceive(NotificationCenter.default.publisher(for: .selectedRegionChanged)) { _ in
                // Region change already triggers refreshes inside YouTubeAPIService.didSet.
                // Avoid duplicating fetches here to prevent visible double-refresh.
                print("🌐 Region changed (view): refresh handled by service")
            }
            
            VStack(spacing: 0) {
                // Category Bar (üstte): yalnızca Ana Sayfa'da ve hiçbir panel açık değilken göster
                let isHome = (selectedSidebarId == "https://www.youtube.com/")
                let noOverlay = (selectedVideo == nil && !showChannelSheet)
                if !youtubeAPI.isShowingSearchResults && isHome && noOverlay {
                    CategoryBarView(youtubeAPI: youtubeAPI, selectedSidebarId: selectedSidebarId)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                Spacer(minLength: 0)
                // Hidden audio host view (keep webview alive)
                HiddenAudioPlayerView(audio: audioPlayer)
                    .frame(width: 1, height: 1)
                    .opacity(0.0)
            }
            .frame(maxWidth: .infinity, alignment: .top)

            // Active tab content overlays the page content area (only video panel area)
            TabHostView(tabs: tabs, youtubeAPI: youtubeAPI)
        }
    .frame(minWidth: 800, minHeight: 600)
    // TabStripView artık SheetManagementView içinden global olarak gösteriliyor
    }
}

// MARK: - AppKit-backed NSSearchField for toolbar sizing
struct ToolbarSearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var width: CGFloat = 220
    var onSubmit: () -> Void

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

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: ToolbarSearchField
        init(_ parent: ToolbarSearchField) { self.parent = parent }

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

        @objc func didSubmit(_ sender: Any?) {
            parent.onSubmit()
        }

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
    MainContentView()
}
