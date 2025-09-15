/*
 Overview / Genel Bakış
 EN: Subscriptions page: latest videos and shorts from subscribed channels, with a bottom channel bar for quick navigation.
 TR: Abonelik sayfası: abone olunan kanallardan en yeni videolar ve Shorts; hızlı gezinme için altta kanal çubuğu.
*/

// EN: Import SwiftUI for building views. TR: Görünümleri oluşturmak için SwiftUI kütüphanesi.
import SwiftUI

struct SubscriptionsView: View {
    // EN: Localization provider for UI strings. TR: UI metinleri için yerelleştirme sağlayıcısı.
    @EnvironmentObject var i18n: Localizer
    // EN: Observable service that holds videos, subscriptions, shorts. TR: Videoları, abonelikleri ve Shorts'u tutan gözlemlenebilir servis.
    @ObservedObject var youtubeAPI: YouTubeAPIService
    // EN: Currently selected channel and whether its sheet is open. TR: Seçili kanal ve panel açık mı.
    @State private var selectedChannel: YouTubeChannel? = nil
    @State private var showChannelSheet: Bool = false
    // EN: Selected video opens the video sheet. TR: Seçilen video paneli açar.
    @State private var selectedVideo: YouTubeVideo? = nil
    // EN: Toggle between all subscriptions feed vs a single channel. TR: Tüm abonelik akışı ile tek kanal görünümü arasında geçiş.
    @State private var showingChannelVideos = false
    // EN: Bottom channel bar scroll state and hover-driven controls. TR: Alt kanal çubuğu kaydırma durumu ve hover tabanlı kontroller.
    @State private var scrollPosition: Int = 0
    @State private var showScrollButtons: Bool = false
    @State private var scrollViewWidth: CGFloat = 0
    @State private var contentWidth: CGFloat = 0
    @State private var isHoveringScrollArea: Bool = false
    @State private var isHoveringLeftArea: Bool = false
    @State private var isHoveringRightArea: Bool = false
    
    // EN: State flags used by SheetManagementView (video/channel/playlist panels). TR: SheetManagementView'in kullandığı durumlar (video/kanal/playlist panelleri).
    @State private var showChannelSearch: Bool = false
    @State private var showChannelView: Bool = false
    @State private var showPlaylistSearch: Bool = false
    @State private var selectedPlaylist: YouTubePlaylist? = nil
    @State private var showPlaylistView: Bool = false
    @State private var showUserChannelInput: Bool = false
    @State private var userChannelURL: String = ""
    
    var body: some View {
        // EN: Wrap page content with shared sheet manager (video/channel/playlist). TR: Sayfa içeriğini ortak panel yöneticisi ile sarar (video/kanal/playlist).
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
                            
                            // EN: Adaptive grid fits 320–420pt cards. TR: 320–420pt arası kartlara uyumlanan ızgara.
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
                        // EN: Latest videos from all subscriptions. TR: Tüm aboneliklerden en yeni videolar.
                        if !youtubeAPI.subscriptionVideos.isEmpty {
                            Text(i18n.t(.latestVideosTitle))
                                .font(.headline)
                                .padding(.horizontal, 20)
                                .padding(.top, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            // EN: Same adaptive grid for feed. TR: Akış için aynı uyarlanabilir ızgara.
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
                    
                    // EN: Shorts rail at the bottom, filtered to subscribed channels. TR: Altta Shorts şeridi; sadece abone olunan kanallar.
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

            // EN: Place bottom channel bar inside safe area to avoid overlay collisions. TR: Alt kanal çubuğunu safe area içine alarak panel çakışmasını önler.
        }
        // Aboneler barını içeriğin üzerine, alt güvenli alana yerleştir
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !youtubeAPI.userSubscriptionsFromURL.isEmpty {
                // EN: Bottom channel bar container. TR: Alt kanal çubuğu kapsayıcısı.
                VStack(alignment: .leading, spacing: 0) {
                    // EN: Reader enables programmatic scrolling by index. TR: Programatik olarak indekse kaydırma için kullanılır.
                    ScrollViewReader { proxy in
                        // EN: Horizontal scroller for subscribed channels. TR: Abone olunan kanallar için yatay kaydırıcı.
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                // EN: Enumerate to get stable numeric IDs. TR: Kararlı sayısal ID'ler için numaralandır.
                                ForEach(Array(youtubeAPI.userSubscriptionsFromURL.enumerated()), id: \.offset) { index, channel in
                                    VStack(spacing: 6) {
                                        // EN: Focus this channel and load its videos. TR: Bu kanala odaklan ve videolarını yükle.
                                        Button(action: {
                                            selectedChannel = channel
                                            showingChannelVideos = true
                                            youtubeAPI.fetchChannelVideos(channelId: channel.id)
                                        }) {
                                            // EN: Channel avatar with loading placeholder. TR: Yükleme yer tutuculu kanal avatarı.
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
                                        // EN: Scroll anchor ID for this chip. TR: Bu öğe için kaydırma çıpası kimliği.
                                        .id(index)

                                        // EN: Channel title under avatar. TR: Avatar altında kanal başlığı.
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
                            // EN: Measure total content width to decide button visibility. TR: Buton görünürlüğü için toplam içerik genişliğini ölç.
                            .background(GeometryReader { geometry in
                                Color.clear
                                    .onAppear { updateContentWidth(geometry.size.width) }
                                    .onChange(of: geometry.size.width) { _, newWidth in
                                        updateContentWidth(newWidth)
                                    }
                            })
                        }
                        // EN: Track visible width of scroller to decide button visibility. TR: Buton görünürlüğü için scroller genişliğini izler.
                        .background(GeometryReader { geometry in
                            Color.clear
                                .onAppear { updateScrollViewWidth(geometry.size.width) }
                                .onChange(of: geometry.size.width) { _, newWidth in
                                    updateScrollViewWidth(newWidth)
                                }
                        })
                        .onChange(of: scrollPosition) { _, newPosition in
                            // EN: Smoothly snap to the new index. TR: Yeni indekse yumuşakça geç.
                            withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(newPosition, anchor: .center) }
                            // EN: Update button visibility after scroll completes. TR: Kaydırma tamamlandıktan sonra buton görünürlüğünü güncelle.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { updateScrollButtonVisibility() }
                        }
                        .overlay(
                            HStack {
                                HStack {
                                    // EN: Show left button when not at start. TR: Başta değilken sol butonu göster.
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
                                // EN: Only toggle hover state when button can show. TR: Buton gösterilebilirken hover durumunu değiştir.
                                .onHover { hovering in if showScrollButtons && scrollPosition > 0 { isHoveringLeftArea = hovering } }

                                Spacer()

                                HStack {
                                    Spacer().frame(maxWidth: 0)
                                    // EN: Show right button when not at end. TR: Sonda değilken sağ butonu göster.
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
                                // EN: Only toggle hover state when button can show. TR: Buton gösterilebilirken hover durumunu değiştir.
                                .onHover { hovering in if showScrollButtons && scrollPosition < youtubeAPI.userSubscriptionsFromURL.count - 1 { isHoveringRightArea = hovering } }
                            }
                        )
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(
                    // EN: Frosted macOS-style material background. TR: macOS tarzı buzlu materyal arka plan.
                    VisualEffectView(material: .titlebar, blendingMode: .withinWindow)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                )
                .overlay(
                    // EN: Subtle outline for separation. TR: Ayırım için ince çerçeve.
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
        // EN: Page background aligned with system control color. TR: Sayfa arka planı sistem kontrol rengiyle uyumlu.
        .background(Color(NSColor.controlBackgroundColor))

        .onAppear {
            // EN: Restore saved subscriptions from local storage. TR: Kayıtlı abonelikleri yerel depodan geri yükle.
            youtubeAPI.loadSubscriptionsFromUserDefaults()
            
            // EN: Fetch feed videos when we have subs but no cached list. TR: Abonelik varsa ama liste boşsa akış videolarını getir.
            if !youtubeAPI.userSubscriptionsFromURL.isEmpty && youtubeAPI.subscriptionVideos.isEmpty {
                youtubeAPI.fetchSubscriptionVideos()
            }
            // EN: Fetch Shorts list if needed. TR: Gerekliyse Shorts listesini getir.
            if youtubeAPI.shortsVideos.isEmpty {
                youtubeAPI.fetchShortsVideos(suppressOverlay: false)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // EN: Show a close button while the video sheet is open. TR: Video paneli açıkken kapatma düğmesini göster.
                if selectedVideo != nil {
                    Button(action: {
                        // EN: Animate closing the video sheet. TR: Video panelini animasyonla kapat.
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
                    // EN: Return to aggregated feed (when showing only a channel). TR: Yalnızca bir kanalı gösterirken toplu akışa dön.
                    Button(i18n.t(.allVideos)) {
                        showingChannelVideos = false
                        selectedChannel = nil
                    }
                }
            }
        }
    }
    
    // MARK: - Scroll Functions
    // EN: Scroll left by three channels (bounded at 0). TR: Üç kanal sola kaydır (0'da sınırla).
    private func scrollLeft() {
        let newPosition = max(0, scrollPosition - 3)
        scrollPosition = newPosition
    }
    
    // EN: Scroll right by three channels (bounded at last index). TR: Üç kanal sağa kaydır (son indekste sınırla).
    private func scrollRight() {
        let totalChannels = youtubeAPI.userSubscriptionsFromURL.count
        let newPosition = min(totalChannels - 1, scrollPosition + 3)
        scrollPosition = newPosition
    }
    
    // EN: Show left/right buttons only when content overflows viewport. TR: İçerik görünüm alanını aştığında sol/sağ butonları göster.
    private func updateScrollButtonVisibility() {
        showScrollButtons = contentWidth > scrollViewWidth
    }

    // EN: Cache total content width and recompute visibility. TR: Toplam içerik genişliğini sakla ve görünürlüğü yeniden hesapla.
    private func updateContentWidth(_ newWidth: CGFloat) {
        contentWidth = newWidth
        updateScrollButtonVisibility()
    }

    // EN: Cache viewport width and recompute visibility. TR: Görünüm alanı genişliğini sakla ve görünürlüğü yeniden hesapla.
    private func updateScrollViewWidth(_ newWidth: CGFloat) {
        scrollViewWidth = newWidth
        updateScrollButtonVisibility()
    }
}



#Preview {
    // EN: Preview with a fresh API service instance. TR: Yeni bir API servis örneği ile önizleme.
    SubscriptionsView(youtubeAPI: YouTubeAPIService())
}