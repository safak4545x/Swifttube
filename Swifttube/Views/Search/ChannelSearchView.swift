

/*
 Overview / Genel Bakış
 EN: Channel search UI that lists results and opens the channel panel on selection.
 TR: Kanal arama arayüzü; sonuçları listeler ve seçimde kanal panelini açar.
*/

// EN: SwiftUI base for the search view. TR: Arama görünümü için SwiftUI temeli.
import SwiftUI

// MARK: - Search Views
// EN: Shows channel search field and results list. TR: Kanal arama alanı ve sonuç listesini gösterir.
struct ChannelSearchView: View {
    // EN: i18n provider for localized strings. TR: Yerelleştirilmiş metinler için i18n sağlayıcı.
    @EnvironmentObject var i18n: Localizer
    // EN: API driving search and results. TR: Arama ve sonuçları yöneten API.
    @ObservedObject var youtubeAPI: YouTubeAPIService
    // EN: Current query text. TR: Geçerli sorgu metni.
    @State private var searchText = ""
    // EN: Bindings to open/close channel sheet and pass selection. TR: Kanal panelini aç/kapat ve seçimi iletmek için binding'ler.
    @Binding var selectedChannel: YouTubeChannel?
    @Binding var showChannelSheet: Bool
    @Binding var showChannelSearch: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // EN: Search header with field and button. TR: Alan ve butondan oluşan arama başlığı.
            HStack {
                TextField(i18n.t(.channels) + " " + i18n.t(.search).lowercased() + "...", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onSubmit {
                        // EN: Submit triggers channel search. TR: Gönderim kanal araması başlatır.
                        youtubeAPI.searchChannels(query: searchText)
                    }
                
                Button(i18n.t(.search)) {
                    // EN: Button triggers channel search. TR: Buton kanal araması başlatır.
                    youtubeAPI.searchChannels(query: searchText)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            
            // EN: Search results area (loading or list). TR: Arama sonuç alanı (yükleme ya da liste).
            if youtubeAPI.isSearching {
                ProgressView(i18n.t(.search) + "...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(youtubeAPI.searchedChannels) { channel in
                            ChannelRowView(channel: channel) {
                                // EN: On selection, set channel, open overlay, close search sheet, and prefetch channel data.
                                // TR: Seçimde kanalı ayarla, paneli aç, arama penceresini kapat ve kanal verilerini önden yükle.
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
        // EN: Title shown in navigation context. TR: Gezinim bağlamında görünen başlık.
        .navigationTitle(i18n.t(.channels))
    }
}
