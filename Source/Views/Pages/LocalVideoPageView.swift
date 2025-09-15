
/*
 File Overview (EN)
 Purpose: Renders a page for locally sourced videos (e.g., from user playlists) using the common card and panel interaction pattern.
 Key Responsibilities:
 - Show local videos with consistent layout
 - Open selected video in overlay and interact with playlist context
 Used By: Playlist-related or local content flows.

 Dosya Özeti (TR)
 Amacı: Yerel kaynaklı videoları (örn. kullanıcı playlist'leri) ortak kart ve panel etkileşimi ile gösteren sayfa.
 Ana Sorumluluklar:
 - Tutarlı düzenle yerel videoları sunmak
 - Seçilen videoyu overlay panelde açmak ve playlist bağlamıyla etkileşmek
 Nerede Kullanılır: Playlist ilişkili veya yerel içerik akışlarında.
*/

import SwiftUI

struct LocalVideoPageView: View {
    let videoId: String
    @ObservedObject var youtubeAPI: YouTubeAPIService

    var body: some View {
        Text("LocalVideoPageView deprecated")
    }
}
