/*
 File Overview (EN)
 Purpose: Main video card used across the app; renders thumbnail, title, channel row, and quick actions.
 Key Responsibilities:
 - Display cached async thumbnail with aspect fit and border
 - Open video on click; support selection highlights and context menu
 - Show metadata (views/date) and subscription badges when applicable
 Used By: Home, related, search, and playlist item lists.

 Dosya Özeti (TR)
 Amacı: Uygulama genelinde kullanılan ana video kartı; küçük resim, başlık, kanal satırı ve hızlı eylemleri sunar.
 Ana Sorumluluklar:
 - Oran koruyan ve kenarlıklı önbellekli küçük resmi göstermek
 - Tıklanınca videoyu açmak; seçim vurguları ve bağlam menüsü desteklemek
 - Uygunsa metadata (görüntülenme/tarih) ve abonelik rozetlerini göstermek
 Nerede Kullanılır: Ana sayfa, ilgili, arama ve oynatma listesi öğe listeleri.
*/

import SwiftUI
import AppKit

struct VideoCardView: View {
    @EnvironmentObject var i18n: Localizer
    let video: YouTubeVideo
    @Binding var selectedVideo: YouTubeVideo?
    @Binding var selectedChannel: YouTubeChannel?
    @Binding var showChannelSheet: Bool
    @ObservedObject var youtubeAPI: YouTubeAPIService
    @EnvironmentObject private var tabs: TabCoordinator
    
    // Video'nun abone kanalından mı geldiğini kontrol et
    private var isFromSubscription: Bool {
        youtubeAPI.userSubscriptionsFromURL.contains { $0.id == video.channelId }
    }
    
    // Canlı yayın rozetini tamamen kaldırdık

    // Kanal adına göre renk üret
    private func generateColor(for channelName: String) -> Color {
        let colors: [Color] = [
            .red, .blue, .green, .orange, .purple, 
            .pink, .cyan, .mint, .indigo, .brown
        ]
        let index = abs(channelName.hashValue) % colors.count
        return colors[index]
    }

    var body: some View {
    VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                // Video thumbnail - tıklanabilir (başlık alt bantta gösterilir)
                Button(action: {
                    selectedVideo = video
                }) {
                    ZStack(alignment: .topTrailing) {
                                CachedAsyncImage(url: URL(string: video.thumbnailURL)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                        }
                        // Kanal paneli ile aynı: 16:9 oran, yükseklik dinamik
                        .aspectRatio(16/9, contentMode: .fill)
                        .background(Color.black)
                        .clipped()
                        .cornerRadius(12)
                        // Kenarlık
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.primary.opacity(0.15), lineWidth: 2)
                        )
                        // Başlığı doğrudan görselin altına sabitle — CANLI/duration rozetlerinden bağımsız
                        .overlay(alignment: .bottomLeading) {
                            HStack(alignment: .bottom) {
                                Text(video.title)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)
                                Spacer(minLength: 0)
                            }
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                            .padding(.horizontal, 8)
                            .padding(.bottom, 8)
                        }

                        // Üst sağ köşe rozetleri (Abone + Canlı veya Süre)
                        VStack(alignment: .trailing, spacing: 6) {
                            if isFromSubscription {
                                HStack(spacing: 4) {
                                    Image(systemName: "bell.fill")
                                        .font(.system(size: 10))
                                    Text(i18n.t(.subscriptions))
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
                            }
                if showLiveBadge {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 6, height: 6)
                    Text(i18n.t(.liveBadge))
                                        .font(.system(size: 10, weight: .medium))
                                        .textCase(.uppercase)
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
                            } else if showDurationBadge {
                                HStack(spacing: 4) {
                                    Text(video.durationText)
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
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
                            }
                        }
                        .padding(.top, 8)
                        .padding(.trailing, 8)

                        // Başlık artık görsel üzerine overlay olarak sabitleniyor (yukarıda)

                        // Abone rozeti üst grup içine taşındı
                    }
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    // Hover efekti için cursor değişimi
                    if hovering {
                        NSCursor.pointingHand.set()
                    } else {
                        NSCursor.arrow.set()
                    }
                }
                .overlay(MouseOpenInNewTabCatcher { // middle-click opens background tab
                    if let idx = tabs.indexOfTab(forVideoId: video.id) {
                        // Already has tab: activate it
                        tabs.activeTabId = tabs.tabs[idx].id
                    } else {
                        tabs.openVideoInBackground(videoId: video.id, title: video.title, isShorts: false)
                    }
                })
                // Sağ tık bağlam menüsü
                .contextMenu {
                    Button(i18n.t(.openInNewTab)) {
                        if let _ = tabs.indexOfTab(forVideoId: video.id) {
                            // zaten varsa arka planda tekrar eklemeyelim; sadece etkinleştirmeyelim
                        } else {
                            tabs.openVideoInBackground(videoId: video.id, title: video.title, isShorts: false)
                        }
                    }
                    Button(i18n.t(.copyLink)) {
                        let link = "https://www.youtube.com/watch?v=\(video.id)"
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(link, forType: .string)
                    }
                    Button(i18n.t(.openInYouTube)) {
                        if let url = URL(string: "https://www.youtube.com/watch?v=\(video.id)") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Button(action: {
                        // Kanal bilgisini API'den al
                    youtubeAPI.fetchChannelInfo(channelId: video.channelId)
                    youtubeAPI.fetchChannelPopularVideos(channelId: video.channelId)
                    // Geçici olarak temel bilgileri ayarla
                    self.selectedChannel = YouTubeChannel(
                        id: video.channelId, title: video.channelTitle,
                            description: i18n.t(.loading) + "...",
                        thumbnailURL: video.channelThumbnailURL.isEmpty ? "https://source.unsplash.com/random/100x100/?profile" : video.channelThumbnailURL,
                        bannerURL: nil)
                    self.showChannelSheet = true
                }) {
                    HStack(spacing: 8) {
                        // Kanal profil fotoğrafı
                        CachedAsyncImage(url: URL(string: video.channelThumbnailURL)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            // Eğer kanal adı varsa ilk harfini göster, yoksa soru işareti
                            Circle()
                                .fill(video.channelTitle.isEmpty ? Color.gray : generateColor(for: video.channelTitle))
                                .overlay(
                                    Text(video.channelTitle.isEmpty ? "?" : String(video.channelTitle.prefix(1)).uppercased())
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.white)
                                )
                        }
                        .frame(width: 24, height: 24)
                        .clipShape(Circle())
                        
                        Text(video.channelTitle)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                    }
                }
                .buttonStyle(.plain)

                // Her zaman sabit yükseklikte bir meta satırı göster — canlı videolarda izleyici sayısını yaz
                HStack(spacing: 6) {
                    if showLiveBadge {
                        // Küçük bir kırmızı nokta + izleyici sayısı (varsa)
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                        if let live = youtubeAPI.liveViewersByVideoId[video.id], !live.isEmpty {
                            Text("\(live) \(i18n.t(.watching))")
                                .font(.system(size: 12, weight: .semibold))
                        } else {
                            Text(i18n.t(.liveBadge))
                                .font(.system(size: 12, weight: .semibold))
                                .textCase(.uppercase)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "eye")
                                .font(.system(size: 11, weight: .semibold))
                            Text(video.viewCount)
                        }
                        Text("•")
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 11, weight: .semibold))
                            Text(video.publishedAt)
                        }
                    }
                }
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(height: 16)
                .onAppear {
                    if showLiveBadge {
                        youtubeAPI.fetchLiveViewersIfNeeded(videoId: video.id)
                    }
                }
            }
            .padding(.horizontal, 6)
        }
    .background(Color.clear)
    // Ebeveyn ızgara sınırlarına sadık kal
    .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
    }
}

// MARK: - Helpers
private extension VideoCardView {
    var showLiveBadge: Bool {
        // Heuristik: Süre yoksa VE (başlık veya publishedAt 'live/canlı' içeriyorsa
        // ya da viewCount/publishedAt boş geldiyse) canlı say.
        if !video.durationText.isEmpty { return false }
        let title = video.title.lowercased()
        let pub = video.publishedAt.lowercased()
        let vc = video.viewCount.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.contains(" live") || title.hasPrefix("live ") || title.contains("canlı") || title.contains(" canlı") {
            return true
        }
        if pub.contains("live") || pub.contains("canlı") || pub.contains("yayında") {
            return true
        }
        if (vc.isEmpty || pub.isEmpty) { // metadata yoksa
            return true
        }
        return false
    }
    var showDurationBadge: Bool {
        guard !showLiveBadge else { return false }
        guard !video.durationText.isEmpty else { return false }
        // Shorts içerikleri için gizle (başlıkta #short / short kelimesi veya çok kısa < 65sn)
        let lower = video.title.lowercased()
        if lower.contains("#short") || lower.contains("#shorts") || lower.contains(" shorts ") || lower.hasPrefix("shorts") { return false }
        if let secs = video.durationSeconds, secs <= 65 { // shorts tipik max ~60s
            // Eğer explicitly #shorts geçmiyorsa yine de gizle
            return false
        }
        return true
    }
}
