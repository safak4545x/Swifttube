/*
 File Overview (EN)
 Purpose: Full video detail page layout combining player, metadata, actions, related list, and playlist panel when applicable.
 Key Responsibilities:
 - Host VideoEmbedView with ambient blur and connect to global controls
 - Render title, channel row, like/share/save actions with localization
 - Show related panel and optional playlist panel; manage layout adaptively
 Used By: Main content router when opening a video.

 Dosya Özeti (TR)
 Amacı: Oynatıcı, metadata, eylemler, ilgili liste ve uygunsa playlist panelini birleştiren tam video detay sayfası yerleşimi.
 Ana Sorumluluklar:
 - Ambient blur ile VideoEmbedView’i barındırmak ve global kontrollere bağlamak
 - Başlık, kanal satırı, beğen/paylaş/kaydet eylemlerini yerelleştirme ile göstermek
 - İlgili panel ve isteğe bağlı playlist panelini göstermek; uyarlanabilir yerleşimi yönetmek
 Nerede Kullanılır: Bir video açıldığında ana içerik yönlendiricisi.
*/

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
    // Global: Ambient blur (lightbulb) tercihini tüm videolarda hatırla
    @AppStorage("global:ambientBlurEnabled") private var showAmbientBlur = false // Shorts tarzı arka plan blur
    @State private var ambientTint: Color? = nil // Dinamik blur için renk
    @State private var lastAmbientTint: Color? = nil
    // PiP dönüşü veya başka kaynaktan belirli saniyeden başlatma
    var resumeSeconds: Double? = nil
    // Playlist mode (optional): when present, render the same Playlist panel on the right and move related videos under it.
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
    
    // Yorumları sıralama fonksiyonu - artık API'den sıralı geliyor
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
            // Use the same background color as HomePageView for visual consistency
            Color(NSColor.controlBackgroundColor)
                .ignoresSafeArea()
            
            GeometryReader { geo in
                // Breakpoint & dynamic sizes
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
                            // Tek bir VideoEmbedView kullanarak layout modları arasında state'in (AVPlayer) sıfırlanmasını engelliyoruz.
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
                                            onTimeUpdate: { t in latestInlineTime = t }
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
                                // Sağ kolon (geniş mod): either playlist panel (if playlist mode) or related videos
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
                                                // Below the playlist panel, show related videos
                                                RelatedVideosView(api: api, onSelect: { selected in
                                                    onOpenVideo?(selected)
                                                })
                                                .frame(maxWidth: .infinity)
                                            } else {
                                                // Fallback: if playlist is not in user list anymore, show related as usual
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
                    .scrollDisabled(disableOuterScroll)
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
                        // Yorum içindeki timestamp tıklanınca player'a otomatik scroll
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo("player", anchor: .top)
                        }
                    }
                }
            }
            .onAppear {
                // İzlenen videoyu geçmişe ekle (her açılışta en üste taşınır)
                api.addToWatchHistory(video)
                // Video detaylarını çek (like count dahil)
                api.fetchVideoDetails(videoId: video.id)
                
                api.fetchChannelInfo(channelId: video.channelId)
                api.fetchRelatedVideos(
                    videoId: video.id, channelId: video.channelId, videoTitle: video.title)
                // Playlist modu aktifse: mevcut videoyu playlist panelinde seçili tutmak için bildir
                if let ctx = effectivePlaylistContext {
                    NotificationCenter.default.post(name: .openPlaylistVideo, object: nil, userInfo: ["playlistId": ctx.playlistId, "videoId": video.id])
                }
                if let resumeSeconds, resumeSeconds > 1 {
                    // Player embed oluşturulduktan sonra seek tetikle
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        NotificationCenter.default.post(name: .seekToSeconds, object: nil, userInfo: ["seconds": Int(resumeSeconds)])
                    }
                }
            }
            .onChange(of: video.id) { _, _ in
                // When switching to another video within the same panel, refresh related/comments etc.
                api.fetchVideoDetails(videoId: video.id)
                api.fetchChannelInfo(channelId: video.channelId)
                api.fetchRelatedVideos(videoId: video.id, channelId: video.channelId, videoTitle: video.title)
                // Playlist modu aktifse: seçimi güncelle
                if let ctx = effectivePlaylistContext {
                    NotificationCenter.default.post(name: .openPlaylistVideo, object: nil, userInfo: ["playlistId": ctx.playlistId, "videoId": video.id])
                }
            }

            // Kapatma butonu artık üst barda, burada gösterilmiyor
        }
        
    }
}