/*
 Overview / Genel Bakış
 EN: Channel details panel with banner (optional blur), stats, description, subscribe actions, and a grid of popular videos.
 TR: Banner (isteğe bağlı blur), istatistikler, açıklama, abone ol/çık eylemleri ve popüler videolar ızgarası içeren kanal detay paneli.
*/

// EN: Import SwiftUI for views and layout. TR: Görünümler ve yerleşimler için SwiftUI kütüphanesi.
import SwiftUI
struct ChannelView: View {
    // EN: Localization provider injected via environment. TR: Ortamdan enjekte edilen yerelleştirme sağlayıcısı.
    @EnvironmentObject var i18n: Localizer
    // EN: Channel whose details will be displayed. TR: Detayları gösterilecek kanal.
    let channel: YouTubeChannel
    // EN: Observable service for fetching data. TR: Veri çekimi için gözlemlenebilir servis.
    @ObservedObject var youtubeAPI: YouTubeAPIService
    // EN: Callback when a grid item is selected. TR: Izgaradan video seçildiğinde çağrılır.
    var onSelectVideo: (YouTubeVideo) -> Void = { _ in }
    // EN: Local list of popular videos for this channel. TR: Bu kanalın popüler videoları için yerel liste.
    @State private var popularVideos: [YouTubeVideo] = []
    // EN: Local loading state for this panel. TR: Bu panel için yerel yükleme durumu.
    @State private var isLoading = true
    // EN: Whether user is subscribed to the channel. TR: Kullanıcı kanalına abone mi?
    @State private var isSubscribed = false
    // EN: Count of visible videos; grows with “Show more”. TR: Görünen video sayısı; “Daha fazlasını göster” ile artar.
    @State private var visibleVideoCount: Int = 12
    // EN: Expanded/collapsed state of long description. TR: Uzun açıklamanın açık/kapalı durumu.
    @State private var isDescriptionExpanded = false
    // EN: Freshly fetched channel info, if available. TR: Varsa çalışma anında çekilen güncel kanal bilgisi.
    @State private var dynamicChannelInfo: YouTubeChannel? = nil 

    // EN: Persist user's preference for ambient bottom blur under banner. TR: Banner altında ortam bulanıklığı tercihini kalıcı tutar.
    @AppStorage("global:channelBannerBlurEnabled") private var showBannerBottomBlur = false
    var body: some View {
        // EN: Use parent geometry to size banner and content adaptively. TR: Banner ve içeriği uyarlamak için üst geometriyi kullan.
        GeometryReader { geo in
            // EN: Horizontal content padding inside the scroll view. TR: ScrollView içeriği için yatay iç boşluk.
            let padding: CGFloat = 16
            // EN: Maintain a comfortable minimum content width. TR: Rahat bir minimum içerik genişliği sağlar.
            let contentWidth = max(800, geo.size.width - padding*2)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // EN: Banner image area with optional blur toggle. TR: İsteğe bağlı blur anahtarlı banner alanı.
                    bannerSection(width: geo.size.width)
                    VStack(alignment: .leading, spacing: 24) {
                        // EN: Avatar, title, stats, description, actions. TR: Avatar, başlık, istatistik, açıklama ve eylemler.
                        headerSection(maxWidth: contentWidth)
                        Divider().padding(.top, 4)
                        // EN: Grid of popular videos with incremental loading. TR: Artımlı yüklemeli popüler videolar ızgarası.
                        popularVideosSection(width: contentWidth)
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, padding)
                    .frame(minWidth: 800, maxWidth: .infinity, alignment: .top)
                }
            }
            // EN: Fetch channel info and popular videos when view appears. TR: Görünüm açılınca kanal bilgisi ve popüler videoları getirir.
            .onAppear(perform: loadData)
            .onChange(of: channel.id) { _, _ in
                // EN: Reset state when switching to a different channel. TR: Farklı kanala geçince durumu sıfırla.
                popularVideos = []
                dynamicChannelInfo = nil
                isDescriptionExpanded = false
                visibleVideoCount = 12
                loadData()
            }
            // EN: Sync local popular list with service updates. TR: Servis güncellemeleriyle yerel popüler listeyi eşitle.
            .onReceive(youtubeAPI.$currentChannelPopularVideos) { vids in
                self.popularVideos = vids.filter { $0.channelId == channel.id }
                self.isLoading = false
                self.visibleVideoCount = 12
            }
            // EN: Update dynamic channel info as soon as it’s fetched. TR: Çekilir çekilmez dinamik kanal bilgisini güncelle.
            .onReceive(youtubeAPI.$channelInfo) { info in
                if let info, info.id == channel.id { dynamicChannelInfo = info }
            }
        }
    .background(Color(NSColor.controlBackgroundColor))
    }
    
    private func bannerSection(width: CGFloat) -> some View {
        // EN: Compute a proportional yet bounded banner height. TR: Orantılı fakat sınırlandırılmış banner yüksekliği hesaplar.
        let targetHeight = max(180, min(width * 0.165, 320))
        // EN: Prefer dynamic banner; fallback to channel banner or neutral image. TR: Önce dinamik, sonra kanal banner’ı; yoksa nötr görsel.
        let bannerURL = (dynamicChannelInfo?.bannerURL ?? channel.bannerURL) ?? "https://source.unsplash.com/random/1920x1080/?music,stage"
        return AsyncImage(url: URL(string: bannerURL)) { image in
            image
                .resizable()
                .scaledToFill()
                .frame(width: width, height: targetHeight)
                .clipped()
        } placeholder: {
            Rectangle()
                .fill(Color.gray.opacity(0.25))
                .frame(width: width, height: targetHeight)
                .shimmering()
        }
        // EN: Subtle bottom fade to improve contrast. TR: Kontrastı artıran hafif alt karartma.
        .overlay(
            LinearGradient(colors: [Color.black.opacity(0.35), Color.black.opacity(0.0)], startPoint: .bottom, endPoint: .top)
        )
        .overlay(alignment: .bottom) {
            // EN: Optional ambient blur under banner. TR: Banner altında isteğe bağlı ortam bulanıklığı.
            if showBannerBottomBlur {
                bannerBottomBlur(width: width, overlayMode: true)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            // EN: Toggle button for showing/hiding bottom blur. TR: Alt bulanıklığı aç/kapat düğmesi.
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { showBannerBottomBlur.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: showBannerBottomBlur ? "lightbulb.fill" : "lightbulb")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 10)
            .padding(.bottom, 10)
        }
        .frame(width: width, height: targetHeight)
        .contentShape(Rectangle())
    }

    private func bannerBottomBlur(width: CGFloat, overlayMode: Bool = false) -> some View {
        // EN: Use same image source to produce a cohesive blur. TR: Tutarlı bulanıklık için aynı görsel kaynağı kullan.
        let bannerURL = (dynamicChannelInfo?.bannerURL ?? channel.bannerURL) ?? "https://source.unsplash.com/random/1920x1080/?music,stage"
        let blurHeight = max(80, min(width * 0.12, 180))
        return AsyncImage(url: URL(string: bannerURL)) { image in
            image
                .resizable()
                .scaledToFill()
                .frame(width: width, height: blurHeight)
                .clipped()
                .blur(radius: 60)
                .saturation(0.92)
                .overlay(Color.black.opacity(0.18))
                .mask(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .white, location: 0.0),
                            .init(color: .white.opacity(0.85), location: 0.35),
                            .init(color: .white.opacity(0.0), location: 1.0)
                        ]),
                        startPoint: .top, endPoint: .bottom
                    )
                )
        } placeholder: {
            Color.clear.frame(width: width, height: blurHeight)
        }
        .frame(width: width, height: blurHeight)
        // EN: When overlaying, push down to sit just below banner. TR: Kaplama modunda bannerın hemen altına it.
        .offset(y: overlayMode ? blurHeight : 0)
        .contentShape(Rectangle())
        .allowsHitTesting(false)
    }
    
    private func headerSection(maxWidth: CGFloat) -> some View {
        // EN: Prefer dynamic info; fall back to initial channel data. TR: Önce dinamik bilgi; yoksa başlangıç kanalı.
        let info = dynamicChannelInfo ?? channel
        return VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 20) {
                AsyncImage(url: URL(string: info.thumbnailURL)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle().fill(Color.gray.opacity(0.3)).shimmering()
                }
                .frame(width: 120, height: 120)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white, lineWidth: 3))
                .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 4)
                
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(info.title)
                            .font(.system(size: 34, weight: .bold))
                            .lineLimit(2)
                        statsLine(info: info)
                    }
                    descriptionBlock(text: info.description)
                    actionButtons(info: info)
                }
                Spacer()
            }
        }
        .frame(maxWidth: maxWidth, alignment: .leading)
    }
    
    private func statsLine(info: YouTubeChannel) -> some View {
        // EN: Show subscriber count or a shimmer placeholder while loading. TR: Yüklenirken parıltı veya abone sayısını göster.
        HStack(spacing: 8) {
            if info.subscriberCount > 0 {
                Text(info.formattedSubscriberCount)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .accessibilityLabel(info.formattedSubscriberCount)
            } else if youtubeAPI.fetchingSubscriberCountIds.contains(info.id) || youtubeAPI.fetchingSubscriberCountIds.isEmpty {
                // Show shimmer while loading or before first batch resolves (ids set might still be empty during debounce)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: 60, height: 12)
                    .shimmering()
                    .accessibilityHidden(true)
            }
        }
    }
    
    
    
    private func descriptionBlock(text: String) -> some View {
        // EN: Offer Read More if text is lengthy or multi-line. TR: Metin uzunsa/çok satırlıysa Devamını Gör sun.
        let needsReadMore = text.count > 260 || text.split(separator: "\n").count > 6
        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                Text(text)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(isDescriptionExpanded ? nil : 6)
                    .fixedSize(horizontal: false, vertical: true)
                if needsReadMore {
                    Button(isDescriptionExpanded ? i18n.t(.showLess) : i18n.t(.readMore)) {
                        withAnimation(.easeInOut) { isDescriptionExpanded.toggle() }
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(6)
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15))
            )
        }
    }
    
    private func actionButtons(info: YouTubeChannel) -> some View {
        // EN: Subscribe/Unsubscribe button and optional notifications action. TR: Abone ol/çık butonu ve opsiyonel bildirim eylemi.
        HStack(spacing: 14) {
            Button(action: toggleSubscription(info)) {
                let subscribed = isSubscribed
                HStack(spacing: 6) {
                    Image(systemName: subscribed ? "xmark" : "plus")
                    Text(subscribed ? i18n.t(.unsubscribe) : i18n.t(.subscribe))
                        .fontWeight(.semibold)
                }
                .font(.system(size: 14))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    Capsule().fill(subscribed ? Color.secondary.opacity(0.15) : Color.accentColor)
                )
                .foregroundColor(subscribed ? .primary : .white)
            }
            .buttonStyle(.plain)
            
            if isSubscribed {
                Button(action: { /* Bildirim ayarları */ }) {
                    Image(systemName: "bell")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                        .padding(10)
                        .background(Circle().fill(Color.secondary.opacity(0.15)))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.top, 4)
    }
    
    private func toggleSubscription(_ channel: YouTubeChannel) -> () -> Void {
        // EN: Flip local state and delegate persistence to service. TR: Yerel durumu değiştirir, kalıcılığı servise bırakır.
        return {
            if isSubscribed {
                youtubeAPI.unsubscribeFromChannel(channel)
                isSubscribed = false
            } else {
                youtubeAPI.subscribeToChannel(channel)
                isSubscribed = true
            }
        }
    }
    
    private func popularVideosSection(width: CGFloat) -> some View {
        // EN: Title + adaptive grid; loads more in batches of 12. TR: Başlık + uyarlanabilir ızgara; 12’lik partilerle artar.
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                Text(i18n.t(.popularVideosTitle))
                    .font(.title2).fontWeight(.bold)
            }
            let columns = adaptiveColumns(for: width)
            LazyVGrid(columns: columns, spacing: 20) {
                let baseVideos = popularVideos
                let videosToShow = Array(baseVideos.prefix(visibleVideoCount))
                ForEach(videosToShow.isEmpty ? [] : videosToShow) { video in
                    VideoCardGridView(video: video) {
                        onSelectVideo(video)
                    }
                }
                if popularVideos.isEmpty { 
                    ForEach(0..<12, id: \.self) { _ in VideoCardSkeletonView() }
                }
            }
            if visibleVideoCount < popularVideos.count {
                Button(action: { withAnimation { visibleVideoCount = min(popularVideos.count, visibleVideoCount + 12) } }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 14))
                        Text(i18n.t(.showMoreVideos))
                            .font(.system(size: 14, weight: .medium))
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        Capsule().fill(Color.accentColor.opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)
            }
        }
    }
    
    private func adaptiveColumns(for width: CGFloat) -> [GridItem] {
        // EN: Decide how many ~320pt cards fit safely in width. TR: Genişliğe yaklaşık 320pt karttan kaç tane sığar, hesaplar.
        let desired: CGFloat = 320
        let count = max(1, Int((width - 32) / desired))
        return Array(repeating: GridItem(.flexible(), spacing: 20), count: count)
    }
    private func loadData() {
        // EN: Request channel info and popular videos; set subscription state. TR: Kanal bilgisi ve popüler videoları ister; abonelik durumunu ayarlar.
        youtubeAPI.fetchChannelPopularVideos(channelId: channel.id)
        youtubeAPI.fetchChannelInfo(channelId: channel.id)
        isSubscribed = youtubeAPI.isSubscribedToChannel(channel.id)
    }
}
