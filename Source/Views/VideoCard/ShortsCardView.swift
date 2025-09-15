/*
 File Overview (EN)
 Purpose: Card UI for Shorts in grid/list contexts with thumbnail, title, and quick actions.
 Key Responsibilities:
 - Show thumbnail with proper aspect, placeholder, and subtle border
 - Display title and channel; open on tap; context menu actions
 - Indicate live/shorts markers as needed
 Used By: Home/Shorts grids and related sections.

 Dosya Özeti (TR)
 Amacı: Küçük resim, başlık ve hızlı eylemlerle grid/liste bağlamındaki Shorts kartı arayüzü.
 Ana Sorumluluklar:
 - Uygun oran, yer tutucu ve ince kenarlıkla küçük resmi göstermek
 - Başlık ve kanalı göstermek; dokununca açmak; bağlam menüsü eylemleri
 - Gerektiğinde canlı/shorts belirteçlerini göstermek
 Nerede Kullanılır: Ana/Shorts gridleri ve ilgili bölümler.
*/

import SwiftUI
import AppKit

// Shorts Card View - Dikey formatta
struct ShortsCardView: View {
    @EnvironmentObject var i18n: Localizer
    let video: YouTubeVideo
    @ObservedObject var youtubeAPI: YouTubeAPIService
    @State private var resolvedThumb: String = ""
    @EnvironmentObject private var tabs: TabCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail - Dikey format
            ZStack(alignment: .bottomTrailing) {
                AsyncImage(url: URL(string: video.thumbnailURL)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                }
                .frame(width: 160, height: 280)
                .clipped()
                .cornerRadius(12)
                .background(Color.black)
                // Orta tık doğrudan görsel üzerinde de yeni sekme açsın
                .overlay(
                    MouseOpenInNewTabCatcher {
                        if let idx = tabs.indexOfTab(forVideoId: video.id) {
                            tabs.activeTabId = tabs.tabs[idx].id
                        } else {
                            tabs.openOrActivate(videoId: video.id, title: video.title, isShorts: true)
                        }
                    }
                    .frame(width: 160, height: 280)
                )

                // Shorts badge — normal video rozetleriyle aynı görünüm
                HStack(spacing: 4) {
                    Image(systemName: "play.square.fill")
                        .font(.system(size: 12))
                    Text(i18n.t(.shorts))
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .padding(.bottom, 8)
                .padding(.trailing, 8)
            }

            // Video info
            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                        // Kanal profil fotoğrafı
                        AsyncImage(url: URL(string: resolvedThumb.isEmpty ? video.channelThumbnailURL : resolvedThumb)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Circle()
                                .fill(Color.gray.opacity(0.3))
                        }
                        .frame(width: 20, height: 20)
                        .clipShape(Circle())
                        
                        Text(video.channelTitle)
                            .font(.system(size: 11))
                            .foregroundColor(.primary)
                    }

                HStack {
                    if !video.viewCount.isEmpty && !video.viewCount.lowercased().hasPrefix("yükleniyor") && !video.viewCount.lowercased().hasPrefix("loading") {
                        Text(video.viewCount)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)

                        Text("•")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    Text(video.publishedAt)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(width: 160)
        .background(Color.clear)
        .padding(.bottom, 8)
        .overlay(MouseOpenInNewTabCatcher {
            if let idx = tabs.indexOfTab(forVideoId: video.id) {
                tabs.activeTabId = tabs.tabs[idx].id
            } else {
                tabs.openVideoInBackground(videoId: video.id, title: video.title, isShorts: true)
            }
        })
        .contextMenu {
            Button(i18n.t(.openInNewTab)) {
                if let _ = tabs.indexOfTab(forVideoId: video.id) {
                    // already exists; do nothing
                } else {
                    tabs.openVideoInBackground(videoId: video.id, title: video.title, isShorts: true)
                }
            }
            Button(i18n.t(.copyLink)) {
                let link = "https://www.youtube.com/shorts/\(video.id)"
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(link, forType: .string)
            }
            Button(i18n.t(.openInYouTube)) {
                if let url = URL(string: "https://www.youtube.com/shorts/\(video.id)") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .task(id: video.id) {
            // Lazy avatar tamamlama: video.channelThumbnailURL boşsa tekil fetch yap
            if video.channelThumbnailURL.isEmpty {
                    if let info = await youtubeAPI.quickChannelInfo(channelId: video.channelId), !info.thumbnailURL.isEmpty {
                    await MainActor.run { self.resolvedThumb = info.thumbnailURL }
                }
            }
        }
    }
}
