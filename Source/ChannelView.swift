/*
 File Overview (EN)
 Purpose: Channel detail panel styled like the video panel. Shows banner with optional bottom blur, dynamic stats, description, subscribe/unsubscribe actions, and popular videos grid.
 Key Responsibilities:
 - Fetch and display channel info + popular videos via YouTubeAPIService
 - Render banner with ambient bottom blur toggle persisted via @AppStorage
 - Show channel stats, description (with Read More), and action buttons
 - Layout an adaptive grid for popular videos with incremental loading
 Used By: Shown as an overlay panel from Search and Subscriptions.

 Dosya Özeti (TR)
 Amacı: Video paneline benzer stilde kanal detay paneli. Banner (isteğe bağlı alt blur), dinamik istatistikler, açıklama, abone ol/çık ve popüler videolar ızgarasını gösterir.
 Ana Sorumluluklar:
 - YouTubeAPIService ile kanal bilgisi ve popüler videoları çekip göstermek
 - @AppStorage ile kalıcı alt blur anahtarlı banner çizmek
 - Kanal istatistikleri, açıklama (Devamını Gör) ve eylem butonlarını sunmak
 - Popüler videolar için uyarlanabilir ızgara ve artımlı yükleme yapmak
 Nerede Kullanılır: Arama ve Abonelikler ekranından panel olarak açılır.
*/

import SwiftUI
struct ChannelView: View {
    @EnvironmentObject var i18n: Localizer
    let channel: YouTubeChannel
    @ObservedObject var youtubeAPI: YouTubeAPIService
    var onSelectVideo: (YouTubeVideo) -> Void = { _ in }
    @State private var popularVideos: [YouTubeVideo] = []
    @State private var isLoading = true
    @State private var isSubscribed = false
    @State private var visibleVideoCount: Int = 12
    @State private var isDescriptionExpanded = false
    @State private var dynamicChannelInfo: YouTubeChannel? = nil 

    @AppStorage("global:channelBannerBlurEnabled") private var showBannerBottomBlur = false
    var body: some View {
        GeometryReader { geo in
            let padding: CGFloat = 16
            let contentWidth = max(800, geo.size.width - padding*2)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    bannerSection(width: geo.size.width)
                    VStack(alignment: .leading, spacing: 24) {
                        headerSection(maxWidth: contentWidth)
                        Divider().padding(.top, 4)
                        popularVideosSection(width: contentWidth)
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, padding)
                    .frame(minWidth: 800, maxWidth: .infinity, alignment: .top)
                }
            }
            .onAppear(perform: loadData)
            .onChange(of: channel.id) { _, _ in
                popularVideos = []
                dynamicChannelInfo = nil
                isDescriptionExpanded = false
                visibleVideoCount = 12
                loadData()
            }
            .onReceive(youtubeAPI.$currentChannelPopularVideos) { vids in
                self.popularVideos = vids.filter { $0.channelId == channel.id }
                self.isLoading = false
                self.visibleVideoCount = 12
            }
            .onReceive(youtubeAPI.$channelInfo) { info in
                if let info, info.id == channel.id { dynamicChannelInfo = info }
            }
        }
    .background(Color(NSColor.controlBackgroundColor))
    }
    
    private func bannerSection(width: CGFloat) -> some View {
        let targetHeight = max(180, min(width * 0.165, 320))
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
        .overlay(
            LinearGradient(colors: [Color.black.opacity(0.35), Color.black.opacity(0.0)], startPoint: .bottom, endPoint: .top)
        )
        .overlay(alignment: .bottom) {
            if showBannerBottomBlur {
                bannerBottomBlur(width: width, overlayMode: true)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottomTrailing) {
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
        .offset(y: overlayMode ? blurHeight : 0)
        .contentShape(Rectangle())
        .allowsHitTesting(false)
    }
    
    private func headerSection(maxWidth: CGFloat) -> some View {
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
        let desired: CGFloat = 320
        let count = max(1, Int((width - 32) / desired))
        return Array(repeating: GridItem(.flexible(), spacing: 20), count: count)
    }
    private func loadData() {
        youtubeAPI.fetchChannelPopularVideos(channelId: channel.id)
        youtubeAPI.fetchChannelInfo(channelId: channel.id)
        isSubscribed = youtubeAPI.isSubscribedToChannel(channel.id)
    }
}
