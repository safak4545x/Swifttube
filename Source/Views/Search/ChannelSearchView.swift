

/*
 File Overview (EN)
 Purpose: Search UI for channels with results list and actions to open channel panel or subscribe.
 Key Responsibilities:
 - Bind to YouTubeAPIService channel search results
 - Render rows via ChannelRowView and handle selection
 Used By: MainContentView toolbar action (search channel).

 Dosya Özeti (TR)
 Amacı: Kanallar için arama arayüzü; sonuç listesi ve kanal paneli açma/abone olma eylemleri.
 Ana Sorumluluklar:
 - YouTubeAPIService kanal arama sonuçlarına bağlanmak
 - ChannelRowView ile satırları çizip seçimleri işlemek
 Nerede Kullanılır: MainContentView araç çubuğu (kanal ara) eylemi.
*/

import SwiftUI

// MARK: - Search Views
struct ChannelSearchView: View {
    @EnvironmentObject var i18n: Localizer
    @ObservedObject var youtubeAPI: YouTubeAPIService
    @State private var searchText = ""
    // Eski showChannelView kullanımı yerine doğrudan gerekli binding'ler
    @Binding var selectedChannel: YouTubeChannel?
    @Binding var showChannelSheet: Bool
    @Binding var showChannelSearch: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Search Header
            HStack {
                TextField(i18n.t(.channels) + " " + i18n.t(.search).lowercased() + "...", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onSubmit {
                        youtubeAPI.searchChannels(query: searchText)
                    }
                
                Button(i18n.t(.search)) {
                    youtubeAPI.searchChannels(query: searchText)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            
            // Search Results
            if youtubeAPI.isSearching {
                ProgressView(i18n.t(.search) + "...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(youtubeAPI.searchedChannels) { channel in
                            ChannelRowView(channel: channel) {
                                // Kanal seçildiğinde: seç, overlay paneli aç, arama sheet'ini kapa
                                selectedChannel = channel
                                showChannelSheet = true
                                showChannelSearch = false
                                // Kanal verilerini önceden yükle
                                youtubeAPI.fetchChannelInfo(channelId: channel.id)
                                youtubeAPI.fetchChannelPopularVideos(channelId: channel.id)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
    .navigationTitle(i18n.t(.channels))
    }
}
