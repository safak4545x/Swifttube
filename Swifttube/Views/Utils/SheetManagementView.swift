/*
 Overview / Genel Bakış
 EN: Page container managing video/channel/playlist overlays and shared UI (tab strip, bottom bar).
 TR: Video/kanal/playlist overlay'lerini ve ortak UI'yi (sekme şeridi, alt çubuk) yöneten kapsayıcı.
*/

import SwiftUI

/// Tüm modallerin yönetimini sağlayan component
struct SheetManagementView<Content: View>: View {
    let content: Content
    @EnvironmentObject private var tabs: TabCoordinator
    @EnvironmentObject private var audioPlayer: AudioPlaylistPlayer
    // EN: Controls whether global TabStrip is shown. TR: Global TabStrip'in görünürlüğünü kontrol eder.
    let showTabStrip: Bool
    // EN: Controls whether BottomPlayerBar is shown. TR: BottomPlayerBar'ın gösterimini kontrol eder.
    @Binding var showBottomPlayerBar: Bool
    
    // EN: Sheet and overlay states. TR: Sheet ve overlay durumları.
    @Binding var selectedVideo: YouTubeVideo?
    @Binding var showChannelSheet: Bool
    @Binding var selectedChannel: YouTubeChannel?
    @Binding var showChannelSearch: Bool
    @Binding var showChannelView: Bool
    @Binding var showPlaylistSearch: Bool
    @Binding var selectedPlaylist: YouTubePlaylist?
    @Binding var showPlaylistView: Bool
    @Binding var showUserChannelInput: Bool
    @Binding var userChannelURL: String
    // EN: Optional resume time when returning from PiP. TR: PiP dönüşünde opsiyonel devam süresi.
    var resumeSeconds: Binding<Double?>? = nil
    
    // API reference
    @ObservedObject var youtubeAPI: YouTubeAPIService
    // EN: Optional playlist context for overlay VideoDetailView. TR: Overlay VideoDetailView için opsiyonel playlist bağlamı.
    @Binding var overlayPlaylistContext: PlaylistContext?
    
    init(
        content: Content,
        selectedVideo: Binding<YouTubeVideo?>,
        showChannelSheet: Binding<Bool>,
        selectedChannel: Binding<YouTubeChannel?>,
        showChannelSearch: Binding<Bool>,
        showChannelView: Binding<Bool>,
        showPlaylistSearch: Binding<Bool>,
        selectedPlaylist: Binding<YouTubePlaylist?>,
        showPlaylistView: Binding<Bool>,
        showUserChannelInput: Binding<Bool>,
        userChannelURL: Binding<String>,
        youtubeAPI: YouTubeAPIService,
        resumeSeconds: Binding<Double?>? = nil,
        showTabStrip: Bool = true,
        showBottomPlayerBar: Binding<Bool>
    ) {
        self.content = content
        self._selectedVideo = selectedVideo
        self._showChannelSheet = showChannelSheet
        self._selectedChannel = selectedChannel
        self._showChannelSearch = showChannelSearch
        self._showChannelView = showChannelView
        self._showPlaylistSearch = showPlaylistSearch
        self._selectedPlaylist = selectedPlaylist
        self._showPlaylistView = showPlaylistView
        self._showUserChannelInput = showUserChannelInput
        self._userChannelURL = userChannelURL
        self.youtubeAPI = youtubeAPI
        self.resumeSeconds = resumeSeconds
        self.showTabStrip = showTabStrip
        self._showBottomPlayerBar = showBottomPlayerBar
        // Default value for backward compatibility; will be injected via convenience init below
        self._overlayPlaylistContext = .constant(nil)
    }

    // Convenience init with overlay playlist context binding
    init(
        content: Content,
        selectedVideo: Binding<YouTubeVideo?>,
        showChannelSheet: Binding<Bool>,
        selectedChannel: Binding<YouTubeChannel?>,
        showChannelSearch: Binding<Bool>,
        showChannelView: Binding<Bool>,
        showPlaylistSearch: Binding<Bool>,
        selectedPlaylist: Binding<YouTubePlaylist?>,
        showPlaylistView: Binding<Bool>,
        showUserChannelInput: Binding<Bool>,
        userChannelURL: Binding<String>,
        youtubeAPI: YouTubeAPIService,
        resumeSeconds: Binding<Double?>? = nil,
        overlayPlaylistContext: Binding<PlaylistContext?>,
        showTabStrip: Bool = true,
        showBottomPlayerBar: Binding<Bool>
    ) {
        self.content = content
        self._selectedVideo = selectedVideo
        self._showChannelSheet = showChannelSheet
        self._selectedChannel = selectedChannel
        self._showChannelSearch = showChannelSearch
        self._showChannelView = showChannelView
        self._showPlaylistSearch = showPlaylistSearch
        self._selectedPlaylist = selectedPlaylist
        self._showPlaylistView = showPlaylistView
        self._showUserChannelInput = showUserChannelInput
        self._userChannelURL = userChannelURL
        self.youtubeAPI = youtubeAPI
        self.resumeSeconds = resumeSeconds
        self._overlayPlaylistContext = overlayPlaylistContext
        self.showTabStrip = showTabStrip
        self._showBottomPlayerBar = showBottomPlayerBar
    }
    
    var body: some View {
        content
            // EN: Video detail panel as full-page overlay. TR: Tam sayfa video detay paneli.
            .overlay(alignment: .center) {
                if let video = selectedVideo {
                    GeometryReader { geo in
                        ZStack {
                            VideoDetailView(
                                video: video,
                                api: youtubeAPI,
                                onClose: {
                                    withAnimation(.easeInOut) {
                                        selectedVideo = nil
                                        overlayPlaylistContext = nil
                                    }
                                },
                                onOpenChannel: { channel in
                                    // EN: Switch from video panel to channel sheet. TR: Video panelinden kanal sheet'ine geç.
                                    withAnimation(.easeInOut) {
                                        selectedVideo = nil
                                        selectedChannel = channel
                                        showChannelSheet = true
                                    }
                                    // Kanal bilgilerini ve popüler videoları getir
                                    youtubeAPI.fetchChannelInfo(channelId: channel.id)
                                    youtubeAPI.fetchChannelPopularVideos(channelId: channel.id)
                                },
                                onOpenVideo: { newVideo in
                                    // EN: Open suggested video in the same overlay panel. TR: Önerilen videoyu aynı panelde aç.
                                    withAnimation(.easeInOut) {
                                        // Eğer overlay playlist modu AKTİFSE ve tıklanan video o playlist'in içindeyse
                                        // bağlamı koru; aksi halde overlay modundan çık.
                                        if let ctx = overlayPlaylistContext {
                                            let isInSamePlaylist = youtubeAPI.cachedPlaylistVideos[ctx.playlistId]?.contains(where: { $0.id == newVideo.id }) ?? false
                                            if !isInSamePlaylist {
                                                overlayPlaylistContext = nil
                                            }
                                        } else {
                                            // Zaten overlay değilsek herhangi bir değişiklik yok
                                        }
                                        selectedVideo = newVideo
                                    }
                                },
                                resumeSeconds: resumeSeconds?.wrappedValue,
                                playlistContext: overlayPlaylistContext
                            )
                            // Video değiştiğinde görünümü yeniden kur ve onAppear tetiklensin
                            .id(video.id)
                            .onAppear {
                                // EN: Clear resume time after use to start from 0 next time. TR: Kullanımdan sonra devam süresini temizle.
                                resumeSeconds?.wrappedValue = nil
                            }
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                        // EN: Overlay transition (slide + tiny scale + fade). TR: Overlay geçişi (kayma + küçük ölçek + solma).
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .trailing)
                                    .combined(with: .scale(scale: 0.98, anchor: .center))
                                    .combined(with: .opacity),
                                removal: .move(edge: .trailing).combined(with: .opacity)
                            )
                        )
                    }
                }
            }
            // Dışarıdan yeni bir video açılırsa ve overlay playlist aktifse: 
            // yeni video o playlist'e ait değilse overlay modundan çık.
            .onChange(of: selectedVideo?.id) { _, _ in
                guard let ctx = overlayPlaylistContext, let v = selectedVideo else { return }
                let stillInPlaylist = youtubeAPI.cachedPlaylistVideos[ctx.playlistId]?.contains(where: { $0.id == v.id }) ?? false
                if !stillInPlaylist {
                    withAnimation(.easeInOut) { overlayPlaylistContext = nil }
                }
            }
            // EN: Channel detail as overlay (same approach as video panel). TR: Kanal detayı overlay (video paneliyle aynı yaklaşım).
            .overlay(alignment: .center) {
                if showChannelSheet, let channel = selectedChannel {
                    GeometryReader { geo in
                        ChannelView(
                            channel: youtubeAPI.channelInfo?.id == channel.id ? (youtubeAPI.channelInfo ?? channel) : channel,
                            youtubeAPI: youtubeAPI,
                            onSelectVideo: { video in
                                withAnimation(.easeInOut) {
                                    selectedVideo = video
                                    showChannelSheet = false
                                }
                            }
                        )
                        .frame(width: geo.size.width, height: geo.size.height)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .onAppear {
                            // EN: Reset previous channel data; ChannelView will load fresh. TR: Eski kanal verisini sıfırla; ChannelView yenisini yükler.
                            youtubeAPI.currentChannelPopularVideos = []
                            youtubeAPI.channelInfo = nil
                        }
                    }
                    .zIndex(2)
                }
            }
            
            // Channel search sheet
            .sheet(isPresented: $showChannelSearch) {
                ChannelSearchView(
                    youtubeAPI: youtubeAPI,
                    selectedChannel: $selectedChannel,
                    showChannelSheet: $showChannelSheet,
                    showChannelSearch: $showChannelSearch
                )
                .frame(minWidth: 800, minHeight: 600)
                // onDisappear gerekmez; state doğrudan yönetiliyor
            }
            
            // Playlist search sheet
            .sheet(isPresented: $showPlaylistSearch) {
                PlaylistSearchView(
                    youtubeAPI: youtubeAPI,
                    selectedPlaylist: $selectedPlaylist,
                    showPlaylistView: $showPlaylistView
                )
                .frame(minWidth: 800, minHeight: 600)
                .onDisappear {
                    if showPlaylistView, let playlist = selectedPlaylist {
                        youtubeAPI.fetchPlaylistVideos(playlistId: playlist.id)
                        showPlaylistView = false
                    }
                }
            }
            
            // User channel input sheet
            .sheet(isPresented: $showUserChannelInput) {
                UserChannelInputView(
                    userChannelURL: $userChannelURL,
                    youtubeAPI: youtubeAPI,
                    onSubmit: { url in
                        youtubeAPI.processUserChannelURL(url)
                        showUserChannelInput = false
                    },
                    onCancel: {
                        showUserChannelInput = false
                    }
                )
                .frame(minWidth: 600, minHeight: 500)
            }
            // EN: Global bottom area: BottomPlayerBar (optional) above TabStrip. TR: Global alt alan: TabStrip'in üstünde opsiyonel BottomPlayerBar.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if showBottomPlayerBar {
                        BottomPlayerBar(audio: audioPlayer)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    if showTabStrip {
                        TabStripView(tabs: tabs)
                    }
                }
            }
    }
}
