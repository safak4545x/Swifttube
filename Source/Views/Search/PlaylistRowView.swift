
/*
 File Overview (EN)
 Purpose: Row component for a single playlist search result showing cover, title, count, and actions.
 Key Responsibilities:
 - Display playlist identity and total count (remote or local)
 - Provide actions to add to user library or open details
 Used By: PlaylistSearchView.

 Dosya Özeti (TR)
 Amacı: Tek bir playlist arama sonucu için satır bileşeni; kapak, başlık, adet ve eylemler içerir.
 Ana Sorumluluklar:
 - Playlist kimliğini ve toplam sayıyı (uzak veya yerel) göstermek
 - Kullanıcı kütüphanesine ekleme veya detay açma eylemleri sağlamak
 Nerede Kullanılır: PlaylistSearchView.
*/

import SwiftUI

struct PlaylistRowView: View {
    @EnvironmentObject var i18n: Localizer
    let playlist: YouTubePlaylist
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                AsyncImage(url: URL(string: playlist.thumbnailURL)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                }
                .frame(width: 80, height: 60)
                .cornerRadius(8)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(playlist.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(playlist.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    
                    if playlist.videoCount > 0 {
                        Text("\(playlist.videoCount) \(i18n.t(.videoCountSuffix))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}
