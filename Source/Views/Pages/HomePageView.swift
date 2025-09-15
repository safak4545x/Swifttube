/*
 File Overview (EN)
 Purpose: Home page that lists recommended (or search result) videos and a horizontal Shorts shelf, with refresh controls and adaptive grid layout.
 Key Responsibilities:
 - Render recommended videos or filtered search results with date/duration filters
 - Provide refresh actions for videos and shorts
 - Present a horizontally scrollable Shorts row with pagination buttons
 - Open video overlay on tap and add to watch history
 Used By: MainContentView when Home is selected.

 Dosya Özeti (TR)
 Amacı: Önerilen (veya arama sonucu) videoları ve yatay Shorts rafını listeleyen ana sayfa; yenileme kontrolleri ve uyarlanabilir ızgara içerir.
 Ana Sorumluluklar:
 - Tarih/süre filtreleriyle önerilen videoları veya arama sonuçlarını göstermek
 - Videolar ve Shorts için yenileme eylemleri sağlamak
 - Sayfalama butonlarıyla yatay kaydırılabilir Shorts satırı sunmak
 - Tıklamada video panelini açmak ve geçmişe eklemek
 Nerede Kullanılır: MainContentView’de Home seçiliyken.
*/

import SwiftUI

struct HomePageView: View {
    @ObservedObject var youtubeAPI: YouTubeAPIService
    @EnvironmentObject private var i18n: Localizer
    @Binding var selectedChannel: YouTubeChannel?
    @Binding var showChannelSheet: Bool
    @Binding var selectedVideo: YouTubeVideo?
    @Binding var selectedSidebarId: String
    @Binding var currentURL: String
    @Binding var currentShortsIndex: Int
    
    // Programatik kaydırma için Shorts rafının mevcut başlangıç indeksi
    @State private var shortsStartIndex: Int = 0
    private let shortsPageStep: Int = 5 // Bir tıkta 5 kart kaydır
    
    var body: some View {
        GeometryReader { geo in
            // Kanal paneli ile aynı padding değeri
            let padding: CGFloat = 16
            let contentWidth = max(800, geo.size.width - padding * 2)
            ScrollView {
                VStack(spacing: 24) {
                // Normal videolar bölümü
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(youtubeAPI.isShowingSearchResults ? i18n.t(.sectionSearchResults) : i18n.t(.sectionRecommended))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        if youtubeAPI.isShowingSearchResults {
                            // Tarih filtresi butonu
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
                            // Süre filtresi butonu
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
                        
                        Button(action: {
                            guard !youtubeAPI.isLoadingVideos else { return }
                            // Eğer arama sonuçları gösteriliyorsa mevcut sorguyu yeniden çalıştır
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
                            // Kart genişliğini kesin olarak sınırla
                            .frame(minWidth: 320, maxWidth: 420)
                            .onTapGesture {
                                // Video geçmişe ekle
                                youtubeAPI.addToWatchHistory(video)
                                selectedVideo = video
                            }
                        }
                    }
                    .padding(.horizontal, padding)
                }
                
                // Shorts bölümü
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
                        
                        Button(action: {
                            guard !youtubeAPI.isLoadingShorts else { return }
                            // If in search mode, refresh search-bound shorts; else reseed shorts for current category
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

                            // SOLA KAYDIR BUTONU
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

                            // SAĞA KAYDIR BUTONU
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
                .padding(.top, 20) // Kategori barın altında az bir boşluk
            }
            .background(Color(NSColor.controlBackgroundColor))
        }
        .onAppear {
            // Arama modunda isek mevcut sonuçları koru; değilse tek seferlik başlangıç yüküne güven
            guard !youtubeAPI.isShowingSearchResults else { return }
            print("📺 HomePageView onAppear — using initialHomeLoad gate")
            youtubeAPI.performInitialHomeLoadIfNeeded()
        }
    }
    
    private func adaptiveColumns(for width: CGFloat) -> [GridItem] {
    // Kart genişliğini sınırla: çok geniş ekranlarda bile kartlar 420px'i geçmesin
    // WatchHistoryView ile tutarlı min/max kullanımı
    _ = width // gelecekte gerekirse kırılımlar için saklı
    return [
        GridItem(.adaptive(minimum: 320, maximum: 420), spacing: 20)
    ]
    }
    
    private var filteredVideos: [YouTubeVideo] {
        youtubeAPI.videos.filter { video in
            let titleLower = video.title.lowercased()
            let descLower = video.description.lowercased()
            let channelLower = video.channelTitle.lowercased()
            
            // Çok kapsamlı Shorts filtreleme - UI seviyesinde de
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
