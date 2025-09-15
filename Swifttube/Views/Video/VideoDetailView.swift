/*
 Overview / Genel Bakış
 EN: Full video detail layout: player + left content, and on wide screens a right sidebar (related or playlist).
 TR: Tam video detay yerleşimi: oynatıcı + sol içerik, geniş ekranda sağ kenar (ilgili veya playlist).
*/

// EN: SwiftUI/AppKit for adaptive layout and app integration (tabs, notifications). TR: Uyarlanabilir yerleşim ve uygulama entegrasyonu için SwiftUI/AppKit.
import SwiftUI
import AppKit

struct VideoDetailView: View {
    @EnvironmentObject var i18n: Localizer
    @EnvironmentObject private var tabs: TabCoordinator
    let video: YouTubeVideo
    @ObservedObject var api: YouTubeAPIService
    let onClose: (() -> Void)?
    // Kanal paneli açma callback'i (video panelinden kanala geçiş)
    let onOpenChannel: ((YouTubeChannel) -> Void)?
    // Önerilen videodan yeni video paneli açma
    let onOpenVideo: ((YouTubeVideo) -> Void)?
    @State private var showShareMenu = false
    @State private var showCommentSortMenu = false
    @State private var commentSortOption: CommentSortOption = .relevance
    @State private var expandedComments: Set<String> = [] // Genişletilmiş yorumları takip et
    @State private var isDescriptionExpanded = false // Video açıklaması için
    @State private var expandedReplies: Set<String> = [] // Yanıtları göster/gizle takibi
    @State private var shouldPlay = true
    // EN: Remember ambient blur preference across videos. TR: Ambient blur tercihini videolar arasında hatırla.
    @AppStorage("global:ambientBlurEnabled") private var showAmbientBlur = false // Shorts tarzı arka plan blur
    @State private var ambientTint: Color? = nil // Dinamik blur için renk
    @State private var lastAmbientTint: Color? = nil
    // PiP dönüşü veya başka kaynaktan belirli saniyeden başlatma
    var resumeSeconds: Double? = nil
    // EN: Optional playlist mode shows playlist panel on the right and puts related underneath. TR: İsteğe bağlı playlist modu sağda panel ve altında ilgili videoları gösterir.
    var playlistContext: PlaylistContext? = nil
    // Inline player'dan mevcut zamanı paylaşması için depolanan değer
    @State private var latestInlineTime: Double = 0
    // While hovering the playlist panel on the right, prevent the main scroll from moving
    @State private var disableOuterScroll: Bool = false
    // Compute an effective playlist context only if the current video actually belongs to that playlist
    private var effectivePlaylistContext: PlaylistContext? {
        guard let ctx = playlistContext else { return nil }
        let contains = api.cachedPlaylistVideos[ctx.playlistId]?.contains(where: { $0.id == video.id }) ?? false
        return contains ? ctx : nil
    }
    
    enum CommentSortOption: String, CaseIterable {
        case mostLiked
        case newest
        case relevance

        var systemImage: String {
            switch self {
            case .mostLiked: return "hand.thumbsup.fill"
            case .newest: return "clock.fill"
            case .relevance: return "star.fill"
            }
        }

        var apiParameter: String {
            switch self {
            case .mostLiked: return "relevance" // YouTube API'de en çok beğeni alan yorumlar genellikle relevance ile gelir
            case .newest: return "time"
            case .relevance: return "relevance"
            }
        }

        @MainActor
        func title(_ i18n: Localizer) -> String {
            switch self {
            case .mostLiked: return i18n.t(.sortMostLiked)
            case .newest: return i18n.t(.sortNewest)
            case .relevance: return i18n.t(.sortRelevance)
            }
        }
    }
    
    // EN: Comment sorting (client-side only for 'most liked'). TR: Yorum sıralama (yalnız 'en beğenilen' için istemci tarafı).
    private var sortedComments: [YouTubeComment] {
        // Client-side sıralama sadece relevance için (çünkü YouTube API bu sıralamayı desteklemiyor)
        if commentSortOption == .mostLiked {
            return api.comments.sorted { $0.likeCount > $1.likeCount }
        } else {
            return api.comments // API'den zaten sıralı geliyor
        }
    }

    var body: some View {
    ZStack(alignment: .topTrailing) {
            // EN: Match background color with HomePageView for visual consistency. TR: Görsel tutarlılık için HomePageView ile aynı arkaplan.
            Color(NSColor.controlBackgroundColor)
                .ignoresSafeArea()
            
            GeometryReader { geo in
                // EN: Breakpoints and dynamic sizes for side layout vs single column. TR: Yan panel vs tek sütun için kırılım ve boyutlar.
                let padding: CGFloat = 16
                let contentWidth = max(600, geo.size.width - padding*2)
                let gutter: CGFloat = 16
                // Three modes
                let normalBreakpoint: CGFloat = 1000   // >= normal: sidebar visible
                let bigBreakpoint: CGFloat = 1650      // Increased big threshold
                let isBig = contentWidth >= bigBreakpoint
                let isSideLayout = contentWidth >= normalBreakpoint
                // Normal & Big panel right column widths
                let rightColumnWidth: CGFloat = isBig ? 360 : 300
                // Left column width when sidebar is visible
                let leftColumnWidth = isSideLayout ? (contentWidth - rightColumnWidth - gutter) : contentWidth
                let playerWidth = leftColumnWidth
                let playerHeight = max(220, playerWidth * 9.0/16.0)
                
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            // EN: Single VideoEmbedView instance to avoid resetting the player across layout modes. TR: Yerleşim modları arasında player state’i sıfırlamamak için tek VideoEmbedView kullan.
                            HStack(alignment: .top, spacing: isSideLayout ? gutter : 0) {
                                VStack(alignment: .leading, spacing: 20) {
                                    ZStack {
                                        if showAmbientBlur {
                                            AmbientBlurAroundPlayer(urlString: video.thumbnailURL, cornerRadius: 12, spread: 220, dynamicTint: ambientTint)
                                        }
                                        VideoEmbedView(
                                            videoId: video.id,
                                            shouldPlay: $shouldPlay,
                                            showAmbientBlur: $showAmbientBlur,
                                            initialStartAt: resumeSeconds,
                                            onColorSampled: { nsColor in
                                                // NSColor -> SwiftUI Color ve yumuşak geçiş
                                                let c = Color(nsColor: nsColor.usingColorSpace(.sRGB) ?? nsColor)
                                                lastAmbientTint = ambientTint
                                                withAnimation(.easeInOut(duration: 0.35)) {
                                                    ambientTint = c
                                                }
                                            },
                                            onTimeUpdate: { t in latestInlineTime = t } // EN: Keep the latest time for handoffs. TR: Devralmalar için son zamanı sakla.
                                        )
                                        // time updates handled via onTimeUpdate
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                    .frame(width: playerWidth, height: playerHeight)
                                    .id("player")
                                    LeftVideoContentView(
                                        video: video,
                                        api: api,
                                        onOpenChannel: { channel in
                                            onOpenChannel?(channel)
                                        },
                                        onClosePanel: { onClose?() },
                                        getCurrentTime: { latestInlineTime },
                                        playlistContext: effectivePlaylistContext
                                    )
                                    .environmentObject(i18n)
                                    .frame(
                                        width: isSideLayout ? leftColumnWidth : nil,
                                        alignment: .leading
                                    )
                                    .frame(maxWidth: isSideLayout ? nil : .infinity, alignment: .leading)
                                }
                                // EN: Right column (wide): playlist panel if in playlist mode, else related videos. TR: Sağ kolon (geniş): playlist modu varsa panel, yoksa ilgili videolar.
                                if isSideLayout {
                                    VStack(spacing: 12) {
                                        if let ctx = effectivePlaylistContext {
                                            // Reuse existing PlaylistView for the same playlist id
                                            if let p = api.userPlaylists.first(where: { $0.id == ctx.playlistId }) ?? api.searchedPlaylists.first(where: { $0.id == ctx.playlistId }) {
                                                PlaylistView(
                                                    youtubeAPI: api,
                                                    playlist: p,
                                                    isSearchResult: false,
                                                    showPlayButton: false,
                                                    openPlaylistId: .constant(ctx.playlistId),
                                                    disableOuterScroll: $disableOuterScroll,
                                                    onRowLeftClick: { vid, _ in
                                                        // Open in the same tab: replace active tab content and keep playlist context
                                                        if let v = api.findVideo(by: vid) {
                                                            tabs.replaceActiveTab(videoId: v.id, title: v.title, isShorts: false, playlist: ctx)
                                                            onOpenVideo?(v)
                                                        } else {
                                                            // Unknown title yet -> placeholder title until enriched
                                                            tabs.replaceActiveTab(videoId: vid, title: "Video", isShorts: false, playlist: ctx)
                                                            onOpenVideo?(YouTubeVideo.makePlaceholder(id: vid))
                                                        }
                                                    },
                                                    onRowMiddleClick: { vid, _ in
                                                        // Middle-click: open in new tab (and activate it)
                                                        if let v = api.findVideo(by: vid) {
                                                            tabs.openOrActivate(videoId: v.id, title: v.title, isShorts: false, playlist: ctx)
                                                        } else {
                                                            tabs.openOrActivate(videoId: vid, title: "Video", isShorts: false, playlist: ctx)
                                                        }
                                                    }
                                                )
                                                .environmentObject(i18n)
                                                .frame(maxWidth: .infinity)
                                                // EN: Show related videos under the playlist panel. TR: Playlist panelinin altında ilgili videoları göster.
                                                RelatedVideosView(api: api, onSelect: { selected in
                                                    onOpenVideo?(selected)
                                                })
                                                .frame(maxWidth: .infinity)
                                            } else {
                                                // EN: Fallback when playlist is missing: just show related. TR: Playlist yoksa: yalnızca ilgili videolar.
                                                RelatedVideosView(api: api, onSelect: { selected in onOpenVideo?(selected) })
                                            }
                                        } else {
                                            RelatedVideosView(api: api, onSelect: { selected in onOpenVideo?(selected) })
                                        }
                                    }
                                    .frame(width: rightColumnWidth)
                                }
                            }
                            .animation(.easeInOut(duration: 0.18), value: isSideLayout)
                            
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 16)
                        .padding(.horizontal, padding)
                        .frame(minWidth: 800, maxWidth: .infinity, minHeight: 700, maxHeight: .infinity, alignment: .top)
                    }
                    // Disable main page scrolling while the mouse is over the right playlist panel
                    .scrollDisabled(disableOuterScroll) // EN: Prevent scroll when hovering the playlist panel. TR: Playlist paneli üzerindeyken kaydırmayı engelle.
                    .onReceive(NotificationCenter.default.publisher(for: .seekToSeconds)) { _ in
                        // Mini Player (PiP) aktifken scroll yapma
                        #if canImport(AppKit)
                        if MiniPlayerWindow.shared.isPresented {
                            return
                        }
                        // Tam ekran açırken de normal paneli otomatik scroll etme
                        if FullscreenPlayerWindow.shared.isPresented {
                            return
                        }
                        #endif
                        // EN: Auto-scroll player into view after clicking a timestamp. TR: Zaman damgasına tıklayınca player’a otomatik kaydır.
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo("player", anchor: .top)
                        }
                    }
                }
            }
            .onAppear {
                // EN: Add to watch history and fetch details/related/channel info. TR: İzleme geçmişine ekle ve detay/ilgili/kanal bilgilerini çek.
                api.addToWatchHistory(video)
                // Video detaylarını çek (like count dahil)
                api.fetchVideoDetails(videoId: video.id)
                
                api.fetchChannelInfo(channelId: video.channelId)
                api.fetchRelatedVideos(
                    videoId: video.id, channelId: video.channelId, videoTitle: video.title)
                // EN: Keep selection synced in the playlist panel when in playlist mode. TR: Playlist modunda paneldeki seçimi senkron tut.
                if let ctx = effectivePlaylistContext {
                    NotificationCenter.default.post(name: .openPlaylistVideo, object: nil, userInfo: ["playlistId": ctx.playlistId, "videoId": video.id])
                }
                if let resumeSeconds, resumeSeconds > 1 {
                    // EN: After embed created, trigger a seek to resume time. TR: Embed oluştuğunda devam zamanına sar.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        NotificationCenter.default.post(name: .seekToSeconds, object: nil, userInfo: ["seconds": Int(resumeSeconds)])
                    }
                }
            }
            .onChange(of: video.id) { _, _ in
                // EN: Switching to another video in the same panel: fetch fresh data and sync playlist selection. TR: Aynı panelde başka videoya geçince verileri yenile ve playlist seçimini güncelle.
                api.fetchVideoDetails(videoId: video.id)
                api.fetchChannelInfo(channelId: video.channelId)
                api.fetchRelatedVideos(videoId: video.id, channelId: video.channelId, videoTitle: video.title)
                // Playlist modu aktifse: seçimi güncelle
                if let ctx = effectivePlaylistContext {
                    NotificationCenter.default.post(name: .openPlaylistVideo, object: nil, userInfo: ["playlistId": ctx.playlistId, "videoId": video.id])
                }
            }

            // EN: Close control is now in the top bar; not shown here. TR: Kapatma kontrolü üst barda; burada yok.
        }
        
    }
}