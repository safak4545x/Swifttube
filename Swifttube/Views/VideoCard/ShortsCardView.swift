/*
 Overview / Genel Bakış
 EN: Shorts card UI with thumbnail, title, channel, and quick actions.
 TR: Küçük resim, başlık, kanal ve hızlı eylemler içeren Shorts kartı.
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
            // EN: Vertical thumbnail layout for Shorts. TR: Shorts için dikey küçük resim düzeni.
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
                // EN: Middle-click on thumbnail opens in a new tab. TR: Küçük resimde orta tık yeni sekmede açar.
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

                // EN: Shorts badge styled like regular badges. TR: Normal rozetlerle aynı stilde Shorts rozeti.
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

            // EN: Basic title/channel/meta section. TR: Basit başlık/kanal/meta bölümü.
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
            // EN: Lazy resolve channel avatar if missing. TR: Kanal avatarı boşsa tembel çözümleme yap.
            if video.channelThumbnailURL.isEmpty {
                    if let info = await youtubeAPI.quickChannelInfo(channelId: video.channelId), !info.thumbnailURL.isEmpty {
                    await MainActor.run { self.resolvedThumb = info.thumbnailURL }
                }
            }
        }
    }
}
