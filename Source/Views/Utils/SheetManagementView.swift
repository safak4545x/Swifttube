
/*
 File Overview (EN)
 Purpose: Page-level container managing overlay sheets/panels (video, channel, playlist) and shared UI like TabStrip and bottom player bar toggles.
 Key Responsibilities:
 - Host content and coordinate overlay presentation via bindings
 - Expose shared controls (tab strip, close actions) in a single place
 - Keep overlay state in sync across pages
 Used By: MainContentView and SubscriptionsView.

 Dosya Özeti (TR)
 Amacı: Sayfa düzeyinde overlay sheet/panel (video, kanal, playlist) yönetimini ve ortak UI'yi (TabStrip, alt çubuk) üstlenen konteyner.
 Ana Sorumluluklar:
 - İçeriği barındırıp binding’ler üzerinden overlay sunumunu koordine etmek
 - Ortak kontrolleri (sekme şeridi, kapatma) tek noktadan sağlamak
 - Overlay durumunu sayfalar arasında senkron tutmak
 Nerede Kullanılır: MainContentView ve SubscriptionsView.
*/

import SwiftUI

/// Tüm modallerin yönetimini sağlayan component
struct SheetManagementView<Content: View>: View {
    let content: Content
    @EnvironmentObject private var tabs: TabCoordinator
    @EnvironmentObject private var audioPlayer: AudioPlaylistPlayer
    // Control whether the global TabStrip should be shown from this wrapper
    let showTabStrip: Bool
    // Control whether the global BottomPlayerBar should be shown (top-level only)
    @Binding var showBottomPlayerBar: Bool
    
    // Sheet states
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
    // PiP dönüşü için opsiyonel resume time
    var resumeSeconds: Binding<Double?>? = nil
    
    // API reference
    @ObservedObject var youtubeAPI: YouTubeAPIService
    // Optional playlist context when opening VideoDetailView as overlay (non-tab)
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
            // Video detail panel as full-page overlay
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
                                    // Video panelinden kanala geçiş
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
                                    // Önerilen videoya tıklanınca ayni panelde yeni videoyu aç
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
                                // Kullanıldıktan sonra temizle ki sonraki açılışlar 0'dan başlasın
                                resumeSeconds?.wrappedValue = nil
                            }
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                        // Video paneli açılış/kapanış animasyonu (kayma + küçük ölçek + opacity)
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
            // Channel detail panel as full-page overlay (video panel ile aynı yaklaşım)
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
                            // Eski kanal popüler videolarını ve info'yu temizle (ChannelView kendi loadData çağıracak)
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
            // Global bottom area pinned: BottomPlayerBar (if requested) stacked above TabStrip
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
