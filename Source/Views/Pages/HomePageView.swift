/*
 Overview / Genel Bakış
 EN: Home page showing recommended/search videos and a horizontal Shorts shelf; includes filters and refresh actions.
 TR: Ana sayfa; önerilen/arama videoları ve yatay Shorts rafı gösterir; filtreler ve yenileme eylemleri içerir.
*/

// EN: SwiftUI for layout and UI components. TR: Düzen ve UI bileşenleri için SwiftUI.
import SwiftUI

// EN: Main Home page listing videos and a Shorts rail. TR: Videolar ve Shorts satırı içeren Ana sayfa.
struct HomePageView: View {
    // EN: API service driving data and flags. TR: Verileri ve bayrakları sağlayan API servisi.
    @ObservedObject var youtubeAPI: YouTubeAPIService
    // EN: Localized strings provider. TR: Yerelleştirilmiş metin sağlayıcı.
    @EnvironmentObject private var i18n: Localizer
    // EN: Bindings to show channel/video overlays and track navigation. TR: Kanal/video panellerini ve gezinmeyi takip için binding'ler.
    @Binding var selectedChannel: YouTubeChannel?
    @Binding var showChannelSheet: Bool
    @Binding var selectedVideo: YouTubeVideo?
    @Binding var selectedSidebarId: String
    @Binding var currentURL: String
    @Binding var currentShortsIndex: Int
    
    // EN: Current pagination index for Shorts shelf. TR: Shorts rafı için mevcut sayfalama indeksi.
    @State private var shortsStartIndex: Int = 0
    // EN: Number of cards to page per click. TR: Her tıkta kaydırılacak kart sayısı.
    private let shortsPageStep: Int = 5
    
    var body: some View {
        GeometryReader { geo in
            // EN: Match channel panel padding. TR: Kanal paneli padding değeriyle eşleştir.
            let padding: CGFloat = 16
            let contentWidth = max(800, geo.size.width - padding * 2)
            ScrollView {
                VStack(spacing: 24) {
                // EN: Regular videos section (recommended or search results). TR: Normal videolar bölümü (önerilen/arama sonuçları).
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(youtubeAPI.isShowingSearchResults ? i18n.t(.sectionSearchResults) : i18n.t(.sectionRecommended))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        if youtubeAPI.isShowingSearchResults {
                            // EN: Date filter chip. TR: Tarih filtresi çipi.
                            Menu {
                                Picker(i18n.t(.date), selection: $youtubeAPI.activeDateFilter) {
                                    ForEach(SearchDateFilter.allCases) { f in
                                        Text(f.display).tag(f)
                                    }
                                }
                                .onChange(of: youtubeAPI.activeDateFilter) { _, _ in
                                    youtubeAPI.searchWithActiveFilters()
                                }
                                Button(i18n.t(.clearFilter)) {
                                    youtubeAPI.activeDateFilter = .none
                                    youtubeAPI.searchWithActiveFilters()
                                }
                            } label: {
                                HStack(spacing:4){
                                    Image(systemName: "calendar")
                                    Text(youtubeAPI.activeDateFilter == .none ? i18n.t(.date) : youtubeAPI.activeDateFilter.display)
                                }
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal,10)
                                .padding(.vertical,4)
                                .background(Color.gray.opacity(0.15))
                                .cornerRadius(12)
                            }
                            .menuStyle(.borderlessButton)
                            // EN: Duration filter chip. TR: Süre filtresi çipi.
                            Menu {
                                Picker(i18n.t(.duration), selection: $youtubeAPI.activeDurationFilter) {
                                    ForEach(SearchDurationFilter.allCases) { f in
                                        Text(f.display).tag(f)
                                    }
                                }
                                .onChange(of: youtubeAPI.activeDurationFilter) { _, _ in
                                    youtubeAPI.searchWithActiveFilters()
                                }
                                Button(i18n.t(.clearFilter)) {
                                    youtubeAPI.activeDurationFilter = .none
                                    youtubeAPI.searchWithActiveFilters()
                                }
                            } label: {
                                HStack(spacing:4){
                                    Image(systemName: "clock")
                                    Text(youtubeAPI.activeDurationFilter == .none ? i18n.t(.duration) : youtubeAPI.activeDurationFilter.display)
                                }
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal,10)
                                .padding(.vertical,4)
                                .background(Color.gray.opacity(0.15))
                                .cornerRadius(12)
                            }
                            .menuStyle(.borderlessButton)
                        }
                        
                        Spacer()
                        
                        // EN: Refresh videos (search or home/custom). TR: Videoları yenile (arama veya ana/özel).
                        Button(action: {
                            guard !youtubeAPI.isLoadingVideos else { return }
                            // EN: If in search mode, rerun current query. TR: Arama modunda ise mevcut sorguyu yeniden çalıştır.
                            let activeQuery = youtubeAPI.currentSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                            if youtubeAPI.isShowingSearchResults, !activeQuery.isEmpty {
                                youtubeAPI.searchVideos(query: activeQuery)
                            } else {
                                if let id = youtubeAPI.selectedCustomCategoryId, let custom = youtubeAPI.customCategories.first(where: { $0.id == id }) {
                                    youtubeAPI.fetchVideos(for: custom, suppressOverlay: true, forceRefresh: true)
                                } else {
                                    youtubeAPI.fetchHomeRecommendations(suppressOverlay: true)
                                }
                            }
                        }) {
                            HStack(spacing: 6) {
                                if youtubeAPI.isLoadingVideos {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 14))
                                }
                                Text(youtubeAPI.isLoadingVideos ? i18n.t(.loading) : i18n.t(.refresh))
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(.blue)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(16)
                            .animation(.easeInOut(duration: 0.15), value: youtubeAPI.isLoadingVideos)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, padding)

                    // EN: Responsive grid of video cards. TR: Video kartlarından oluşan duyarlı ızgara.
                    LazyVGrid(
                        columns: adaptiveColumns(for: contentWidth),
                        spacing: 20
                    ) {
                        ForEach(filteredVideos) { video in
                            VideoCardView(
                                video: video,
                                selectedVideo: $selectedVideo,
                                selectedChannel: $selectedChannel,
                                showChannelSheet: $showChannelSheet,
                                youtubeAPI: youtubeAPI
                            )
                            // EN: Constrain card width for consistent look. TR: Tutarlı görünüm için kart genişliğini sınırla.
                            .frame(minWidth: 320, maxWidth: 420)
                            .onTapGesture {
                                // EN: Add to watch history and open overlay. TR: İzleme geçmişine ekle ve paneli aç.
                                youtubeAPI.addToWatchHistory(video)
                                selectedVideo = video
                            }
                        }
                    }
                    .padding(.horizontal, padding)
                }
                
                // EN: Shorts shelf with horizontal paging. TR: Yatay sayfalama ile Shorts bölümü.
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        HStack(spacing: 8) {
                            Image(systemName: "play.square.fill")
                                .foregroundColor(.red)
                                .font(.system(size: 20))
                            Text(i18n.t(.shorts))
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                        }
                        
                        Spacer()
                        
                        // EN: Refresh Shorts (search-bound or reseed). TR: Shorts'u yenile (arama bağlı veya yeniden tohumla).
                        Button(action: {
                            guard !youtubeAPI.isLoadingShorts else { return }
                            // EN: In search mode refresh those; else reseed for current category. TR: Arama modunda onları yenile; değilse mevcut kategori için yeniden tohumla.
                            if youtubeAPI.isShowingSearchResults, !youtubeAPI.currentSearchQuery.isEmpty {
                                youtubeAPI.refreshSearchShorts()
                            } else {
                                youtubeAPI.fetchShortsVideos(suppressOverlay: true, forceRefresh: true)
                            }
                        }) {
                            HStack(spacing: 6) {
                                if youtubeAPI.isLoadingShorts {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 14))
                                }
                                Text(youtubeAPI.isLoadingShorts ? i18n.t(.loading) : i18n.t(.refresh))
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(.red)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(16)
                            .animation(.easeInOut(duration: 0.15), value: youtubeAPI.isLoadingShorts)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, padding)

                    ZStack {
                        ScrollViewReader { proxy in
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(youtubeAPI.shortsVideos) { video in
                                        ShortsCardView(
                                            video: video,
                                            youtubeAPI: youtubeAPI
                                        )
                                        .id(video.id)
                                        .onTapGesture {
                                            // EN: Route to Shorts page and focus selected card index. TR: Shorts sayfasına git ve seçili kart indeksini odakla.
                                            selectedSidebarId = "https://www.youtube.com/shorts"
                                            currentURL = "https://www.youtube.com/shorts"
                                            if let shortsIndex = youtubeAPI.shortsVideos
                                                .firstIndex(where: { $0.id == video.id })
                                            {
                                                currentShortsIndex = shortsIndex
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, padding)
                            }

                            // EN: Page left through Shorts cards. TR: Shorts kartlarında sola sayfala.
                            .overlay(alignment: .leading) {
                                if !youtubeAPI.shortsVideos.isEmpty {
                                    let canGoLeft = shortsStartIndex > 0
                                    Button {
                                        guard canGoLeft else { return }
                                        let newIndex = max(0, shortsStartIndex - shortsPageStep)
                                        if !youtubeAPI.shortsVideos.isEmpty {
                                            withAnimation(.easeOut(duration: 0.25)) {
                                                proxy.scrollTo(youtubeAPI.shortsVideos[newIndex].id, anchor: .leading)
                                            }
                                            shortsStartIndex = newIndex
                                        }
                                    } label: {
                                        Image(systemName: "chevron.left")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundColor(.primary)
                                            .frame(width: 28, height: 28)
                                    }
                                    .buttonStyle(.plain)
                                    .background(
                                        VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                                            .clipShape(Circle())
                                    )
                                    .overlay(
                                        Circle().stroke(Color.white.opacity(0.08), lineWidth: 1)
                                    )
                                    .opacity(canGoLeft ? 1.0 : 0.35)
                                    .disabled(!canGoLeft)
                                    .padding(.leading, 4)
                                }
                            }

                            // EN: Page right through Shorts cards. TR: Shorts kartlarında sağa sayfala.
                            .overlay(alignment: .trailing) {
                                if !youtubeAPI.shortsVideos.isEmpty {
                                    let lastStart = max(0, youtubeAPI.shortsVideos.count - 1 - shortsPageStep)
                                    let canGoRight = shortsStartIndex < lastStart
                                    Button {
                                        guard canGoRight else { return }
                                        let newIndex = min(shortsStartIndex + shortsPageStep, youtubeAPI.shortsVideos.count - 1)
                                        if !youtubeAPI.shortsVideos.isEmpty {
                                            withAnimation(.easeOut(duration: 0.25)) {
                                                proxy.scrollTo(youtubeAPI.shortsVideos[newIndex].id, anchor: .leading)
                                            }
                                            shortsStartIndex = newIndex
                                        }
                                    } label: {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundColor(.primary)
                                            .frame(width: 28, height: 28)
                                    }
                                    .buttonStyle(.plain)
                                    .background(
                                        VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                                            .clipShape(Circle())
                                    )
                                    .overlay(
                                        Circle().stroke(Color.white.opacity(0.08), lineWidth: 1)
                                    )
                                    .opacity(canGoRight ? 1.0 : 0.35)
                                    .disabled(!canGoRight)
                                    .padding(.trailing, 4)
                                }
                            }
                        }
                    }
                }
                }
                .padding(.vertical, 20)
                .padding(.top, 20) // EN: Small gap under category bar. TR: Kategori çubuğu altında küçük boşluk.
            }
            .background(Color(NSColor.controlBackgroundColor))
        }
        .onAppear {
            // EN: Avoid refetch if already in search mode; otherwise do initial home load once. TR: Arama modundaysa tekrar çekme; değilse bir kez başlangıç yüklemesi yap.
            guard !youtubeAPI.isShowingSearchResults else { return }
            print("📺 HomePageView onAppear — using initialHomeLoad gate")
            youtubeAPI.performInitialHomeLoadIfNeeded()
        }
    }
    
    // EN: Grid columns with clamped card width. TR: Sınırlandırılmış kart genişliğiyle ızgara sütunları.
    private func adaptiveColumns(for width: CGFloat) -> [GridItem] {
    // EN: Keep up to 420px for readability; consistent with WatchHistoryView. TR: Okunabilirlik için 420px'e kadar; WatchHistoryView ile tutarlı.
    _ = width // gelecekte gerekirse kırılımlar için saklı
    return [
        GridItem(.adaptive(minimum: 320, maximum: 420), spacing: 20)
    ]
    }
    
    // EN: Filter out likely Shorts and vertical/mobile content. TR: Muhtemel Shorts ve dikey/mobil içerikleri ele.
    private var filteredVideos: [YouTubeVideo] {
        youtubeAPI.videos.filter { video in
            let titleLower = video.title.lowercased()
            let descLower = video.description.lowercased()
            let channelLower = video.channelTitle.lowercased()
            
            // EN: Comprehensive UI-level Shorts filtering. TR: Kapsamlı UI seviyesinde Shorts filtreleme.
            return !isUnderOneMinute(video) &&
                   !titleLower.contains("shorts") && 
                   !titleLower.contains("#shorts") &&
                   !titleLower.contains("short") &&
                   !descLower.contains("#shorts") &&
                   !descLower.contains("shorts") &&
                   !descLower.contains("short") &&
                   !channelLower.contains("shorts") &&
                   !titleLower.contains("vertical") &&
                   !titleLower.contains("mobile") &&
                   !titleLower.contains("#short") &&
                   !titleLower.contains("#viral") &&
                   !titleLower.contains("#trending") &&
                   !descLower.contains("#short") &&
                   !descLower.contains("#viral") &&
                   !titleLower.contains("ytshorts") &&
                   !titleLower.contains("yt shorts") &&
                   !descLower.contains("ytshorts") &&
                   !descLower.contains("yt shorts")
        }
    }
}
