/*
 File Overview (EN)
 Purpose: Subscriptions page showing latest videos and shorts from the user's subscribed channels, plus a bottom inline bar listing channels for quick navigation.
 Key Responsibilities:
 - Display subscription feed or a selected channel's videos
 - Provide bottom scrollable channel bar with hover-based scroll controls
 - Integrate with SheetManagementView to open video and channel panels
 - Trigger initial fetches for subscription videos and shorts
 Used By: MainContentView when the Subscriptions page is active.

 Dosya Özeti (TR)
 Amacı: Kullanıcının abone olduğu kanallardan gelen en yeni videoları ve Shorts'ları gösteren sayfa; hızlı gezinme için altta kanal barı sunar.
 Ana Sorumluluklar:
 - Abonelik akışını veya seçili kanalın videolarını listelemek
 - Üzerine gelince görünen kontrol butonlarıyla kaydırılabilir alt kanal barı sağlamak
 - Video ve kanal panellerini açmak için SheetManagementView ile entegre çalışmak
 - Abonelik videoları ve Shorts için ilk veri çekimlerini tetiklemek
 Nerede Kullanılır: MainContentView'de Abonelikler sekmesi aktifken.
*/

import SwiftUI

struct SubscriptionsView: View {
    @EnvironmentObject var i18n: Localizer
    @ObservedObject var youtubeAPI: YouTubeAPIService
    @State private var selectedChannel: YouTubeChannel? = nil
    @State private var showChannelSheet: Bool = false
    @State private var selectedVideo: YouTubeVideo? = nil
    @State private var showingChannelVideos = false
    @State private var scrollPosition: Int = 0
    @State private var showScrollButtons: Bool = false
    @State private var scrollViewWidth: CGFloat = 0
    @State private var contentWidth: CGFloat = 0
    @State private var isHoveringScrollArea: Bool = false
    @State private var isHoveringLeftArea: Bool = false
    @State private var isHoveringRightArea: Bool = false
    
    // SheetManagementView için gerekli state'ler
    @State private var showChannelSearch: Bool = false
    @State private var showChannelView: Bool = false
    @State private var showPlaylistSearch: Bool = false
    @State private var selectedPlaylist: YouTubePlaylist? = nil
    @State private var showPlaylistView: Bool = false
    @State private var showUserChannelInput: Bool = false
    @State private var userChannelURL: String = ""
    
    var body: some View {
        SheetManagementView(
            content: mainContent,
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
            showTabStrip: false,
            showBottomPlayerBar: .constant(false)
        )
    }
    
    @ViewBuilder
    private var mainContent: some View {
    VStack(spacing: 0) {
            // Videolar bölümü
            ScrollView {
                LazyVStack(spacing: 12) {
                    if showingChannelVideos {
                        // Seçilen kanalın videoları
                        if !youtubeAPI.channelVideos.isEmpty {
                            HStack {
                                Text("\(selectedChannel?.title ?? i18n.t(.channels)) \(i18n.t(.videos))")
                                    .font(.headline)
                                
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                            LazyVGrid(
                                columns: [
                                    GridItem(
                                        .adaptive(minimum: 320, maximum: 420), spacing: 32)
                                ], spacing: 32
                            ) {
                                ForEach(youtubeAPI.channelVideos) { video in
                                    VideoCardView(
                                        video: video,
                                        selectedVideo: $selectedVideo,
                                        selectedChannel: $selectedChannel,
                                        showChannelSheet: $showChannelSheet,
                                        youtubeAPI: youtubeAPI
                                    )
                                }
                            }
                            .padding(.horizontal, 12)
                        } else if youtubeAPI.isLoading {
                            ProgressView(i18n.t(.videosLoading))
                                .padding(.top, 20)
                        }
                    } else {
                        // Tüm aboneliklerin en yeni videoları
                        if !youtubeAPI.subscriptionVideos.isEmpty {
                            Text(i18n.t(.latestVideosTitle))
                                .font(.headline)
                                .padding(.horizontal, 20)
                                .padding(.top, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            LazyVGrid(
                                columns: [
                                    GridItem(
                                        .adaptive(minimum: 320, maximum: 420), spacing: 32)
                                ], spacing: 32
                            ) {
                                ForEach(youtubeAPI.subscriptionVideos) { video in
                                    VideoCardView(
                                        video: video,
                                        selectedVideo: $selectedVideo,
                                        selectedChannel: $selectedChannel,
                                        showChannelSheet: $showChannelSheet,
                                        youtubeAPI: youtubeAPI
                                    )
                                }
                            }
                            .padding(.horizontal, 12)
                        } else if youtubeAPI.isLoading {
                            ProgressView(i18n.t(.subscriptionsLoading))
                                .padding(.top, 20)
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "person.2.circle")
                                    .font(.system(size: 40))
                                    .foregroundColor(.secondary)
                                Text(i18n.t(.noSubscriptionsYet))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text(i18n.t(.addSubscriptionsHint))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 40)
                            }
                            .padding(.top, 40)
                        }
                    }
                    
                    // Shorts bölümü (en altta)
                    if !youtubeAPI.shortsVideos.isEmpty {
                        let subscriptionShorts = youtubeAPI.shortsVideos.filter { video in
                            // Sadece abone olunan kanalların shorts'ları
                            youtubeAPI.userSubscriptionsFromURL.contains { channel in
                                channel.id == video.channelId
                            }
                        }
                        
                        if !subscriptionShorts.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Divider()
                                    .padding(.top, 16)
                                
                                Text(i18n.t(.subscriptionsShortsTitle))
                                    .font(.headline)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 8)
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(subscriptionShorts) { video in
                                            ShortsCardView(video: video, youtubeAPI: youtubeAPI)
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                }
                            }
                            .padding(.bottom, 16)
                        }
                    }
                }
            }

            // Alt bar artık safeAreaInset ile ekleniyor (arka panel çakışmalarını önlemek için)
        }
        // Aboneler barını içeriğin üzerine, alt güvenli alana yerleştir
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !youtubeAPI.userSubscriptionsFromURL.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(Array(youtubeAPI.userSubscriptionsFromURL.enumerated()), id: \.offset) { index, channel in
                                    VStack(spacing: 6) {
                                        Button(action: {
                                            selectedChannel = channel
                                            showingChannelVideos = true
                                            youtubeAPI.fetchChannelVideos(channelId: channel.id)
                                        }) {
                                            AsyncImage(url: URL(string: channel.thumbnailURL)) { image in
                                                image.resizable().aspectRatio(contentMode: .fill)
                                            } placeholder: {
                                                Circle().fill(Color.gray.opacity(0.3)).overlay(ProgressView().scaleEffect(0.6))
                                            }
                                            .frame(width: 56, height: 56)
                                            .clipShape(Circle())
                                            .overlay(Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                                        }
                                        .buttonStyle(.plain)
                                        .id(index)

                                        Text(channel.title)
                                            .font(.caption2)
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                            .multilineTextAlignment(.center)
                                            .frame(width: 64, height: 16)
                                    }
                                }
                            }
                            .padding(.horizontal, 8)
                            .background(GeometryReader { geometry in
                                Color.clear
                                    .onAppear { updateContentWidth(geometry.size.width) }
                                    .onChange(of: geometry.size.width) { _, newWidth in
                                        updateContentWidth(newWidth)
                                    }
                            })
                        }
                        .background(GeometryReader { geometry in
                            Color.clear
                                .onAppear { updateScrollViewWidth(geometry.size.width) }
                                .onChange(of: geometry.size.width) { _, newWidth in
                                    updateScrollViewWidth(newWidth)
                                }
                        })
                        .onChange(of: scrollPosition) { _, newPosition in
                            withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(newPosition, anchor: .center) }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { updateScrollButtonVisibility() }
                        }
                        .overlay(
                            HStack {
                                HStack {
                                    if showScrollButtons && scrollPosition > 0 {
                                        Button(action: { scrollLeft() }) {
                                            Image(systemName: "chevron.left")
                                                .font(.system(size: 16, weight: .medium))
                                                .foregroundColor(.secondary)
                                                .frame(width: 32, height: 32)
                                                .background(.ultraThinMaterial)
                                                .cornerRadius(8)
                                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                                        }
                                        .buttonStyle(.plain)
                                        .opacity(isHoveringLeftArea ? 1.0 : 0.0)
                                        .animation(.easeInOut(duration: 0.2), value: isHoveringLeftArea)
                                    }
                                    Spacer().frame(maxWidth: 0)
                                }
                                .frame(width: 50)
                                .padding(.leading, 8)
                                .onHover { hovering in if showScrollButtons && scrollPosition > 0 { isHoveringLeftArea = hovering } }

                                Spacer()

                                HStack {
                                    Spacer().frame(maxWidth: 0)
                                    if showScrollButtons && scrollPosition < youtubeAPI.userSubscriptionsFromURL.count - 1 {
                                        Button(action: { scrollRight() }) {
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 16, weight: .medium))
                                                .foregroundColor(.secondary)
                                                .frame(width: 32, height: 32)
                                                .background(.ultraThinMaterial)
                                                .cornerRadius(8)
                                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                                        }
                                        .buttonStyle(.plain)
                                        .opacity(isHoveringRightArea ? 1.0 : 0.0)
                                        .animation(.easeInOut(duration: 0.2), value: isHoveringRightArea)
                                    }
                                }
                                .frame(width: 50)
                                .padding(.trailing, 8)
                                .onHover { hovering in if showScrollButtons && scrollPosition < youtubeAPI.userSubscriptionsFromURL.count - 1 { isHoveringRightArea = hovering } }
                            }
                        )
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(
                    VisualEffectView(material: .titlebar, blendingMode: .withinWindow)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))

        .onAppear {
            // Önce kayıtlı abonelikleri yükle
            youtubeAPI.loadSubscriptionsFromUserDefaults()
            
            // Sayfa açıldığında abonelik videolarını yükle
            if !youtubeAPI.userSubscriptionsFromURL.isEmpty && youtubeAPI.subscriptionVideos.isEmpty {
                youtubeAPI.fetchSubscriptionVideos()
            }
            // Shorts videoları da yükle
            if youtubeAPI.shortsVideos.isEmpty {
                youtubeAPI.fetchShortsVideos(suppressOverlay: false)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // Video paneli açıkken kapatma butonu göster
                if selectedVideo != nil {
                    Button(action: {
                        withAnimation(.easeInOut) { selectedVideo = nil }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18, weight: .regular))
                            .symbolRenderingMode(.monochrome)
                    }
                    .help(i18n.t(.closePanelHint))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
                } else if showingChannelVideos {
                    // Sadece kanal videoları görünürken ve video paneli kapalıyken göster
                    Button(i18n.t(.allVideos)) {
                        showingChannelVideos = false
                        selectedChannel = nil
                    }
                }
            }
        }
    }
    
    // MARK: - Scroll Functions
    private func scrollLeft() {
        // Birkaç kanal geriye git
        let newPosition = max(0, scrollPosition - 3)
        scrollPosition = newPosition
    }
    
    private func scrollRight() {
        // Birkaç kanal ileriye git
        let totalChannels = youtubeAPI.userSubscriptionsFromURL.count
        let newPosition = min(totalChannels - 1, scrollPosition + 3)
        scrollPosition = newPosition
    }
    
    private func updateScrollButtonVisibility() {
        showScrollButtons = contentWidth > scrollViewWidth
    }

    // Tekrarlayan genişlik güncellemelerini sadeleştir
    private func updateContentWidth(_ newWidth: CGFloat) {
        contentWidth = newWidth
        updateScrollButtonVisibility()
    }

    private func updateScrollViewWidth(_ newWidth: CGFloat) {
        scrollViewWidth = newWidth
        updateScrollButtonVisibility()
    }
}



#Preview {
    SubscriptionsView(youtubeAPI: YouTubeAPIService())
}