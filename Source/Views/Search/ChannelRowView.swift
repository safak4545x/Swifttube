
/*
 File Overview (EN)
 Purpose: Row component representing a single channel search result with thumbnail, title, and actions.
 Key Responsibilities:
 - Display channel identity and basic stats
 - Provide actions like open details or subscribe
 Used By: ChannelSearchView.

 Dosya Özeti (TR)
 Amacı: Tek bir kanal arama sonucunu temsil eden satır bileşeni; küçük resim, başlık ve eylemler içerir.
 Ana Sorumluluklar:
 - Kanal kimliğini ve temel istatistikleri göstermek
 - Detayları açma veya abone olma gibi eylemler sağlamak
 Nerede Kullanılır: ChannelSearchView.
*/

import SwiftUI

struct ChannelRowView: View {
    let channel: YouTubeChannel
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                AsyncImage(url: URL(string: channel.thumbnailURL)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                }
                .frame(width: 60, height: 60)
                .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(channel.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(channel.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
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
