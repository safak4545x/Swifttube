/*
 Overview / Genel Bakış
 EN: Right-side list of related videos with loading states, quick actions, and live/shorts heuristics.
 TR: Yükleme durumları, hızlı eylemler ve canlı/shorts sezgileri olan sağ taraftaki ilgili videolar listesi.
*/

// EN: SwiftUI/AppKit for list UI and clipboard/open actions. TR: Liste arayüzü ve panoya kopyala/aç işlemleri için SwiftUI/AppKit.
import SwiftUI
import AppKit

// EN: Related list beside the main player; selecting an item opens it. TR: Ana oynatıcı yanında ilgili liste; seçimle video açılır.
struct RelatedVideosView: View {
    @EnvironmentObject var i18n: Localizer
    @ObservedObject var api: YouTubeAPIService
    var onSelect: ((YouTubeVideo) -> Void)?
    @EnvironmentObject private var tabs: TabCoordinator
    
    init(api: YouTubeAPIService, onSelect: ((YouTubeVideo) -> Void)? = nil) {
        self.api = api
        self.onSelect = onSelect
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // EN: Section title. TR: Bölüm başlığı.
            Text(i18n.t(.recommendedVideosTitle))
                .font(.headline)
                .padding(.bottom, 4)

            if api.relatedVideos.isEmpty {
                if api.isLoadingRelated {
                    // EN: Loading state with spinner. TR: Yükleniyor durumu ve dönen gösterge.
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(i18n.t(.recommendedLoading))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
                } else {
                    // EN: Empty state when nothing is available. TR: Veri yokken boş durum mesajı.
                    Text(i18n.t(.recommendedNone))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                }
            } else {
                // EN: Show only items with a real title (avoid id-only placeholders). TR: Sadece gerçek başlıklı öğeleri göster (yalnız id olanları filtrele).
                let displayable = api.relatedVideos.filter { !$0.title.isEmpty && $0.title != $0.id }
                // EN: Cap to a small set to keep the sidebar compact. TR: Kenar alanı derli toplu tutmak için küçük bir kümeyle sınırla.
                ForEach(displayable.prefix(8)) { relatedVideo in
                    Button(action: {
                        onSelect?(relatedVideo)
                    }) {
                        HStack(spacing: 8) {
                            // EN: Thumbnail. TR: Küçük görsel.
                            AsyncImage(url: URL(string: relatedVideo.thumbnailURL)) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                            }
                            .frame(width: 120, height: 68)
                            .background(Color.black)
                            .clipped()
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.primary.opacity(0.15), lineWidth: 2)
                            )

                            VStack(alignment: .leading, spacing: 4) {
                                // EN: Title (id-only cases already filtered). TR: Başlık (yalnız id olanlar zaten filtrelendi).
                                Text(relatedVideo.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .lineLimit(2)

                                HStack(alignment: .center, spacing: 6) {
                                    // EN: Channel avatar (if available) + channel title. TR: Kanal avatarı (varsa) + kanal adı.
                                    if let url = URL(string: relatedVideo.channelThumbnailURL), !relatedVideo.channelThumbnailURL.isEmpty {
                                        AsyncImage(url: url) { img in
                                            img.resizable().scaledToFill()
                                        } placeholder: {
                                            Circle().fill(Color.gray.opacity(0.2))
                                        }
                                        .frame(width: 16, height: 16)
                                        .clipShape(Circle())
                                    }
                                    Text(relatedVideo.channelTitle.isEmpty ? "Kanal" : relatedVideo.channelTitle)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }

                                // EN: Meta row — live badge/viewers vs. views + published date. TR: Meta satırı — canlı rozet/izleyici veya izlenme + yayın tarihi.
                                HStack(spacing: 4) {
                                    if isLiveLike(relatedVideo) {
                                        // EN: Small red dot + live viewers (if available). TR: Küçük kırmızı nokta + izleyici sayısı (varsa).
                                        Circle()
                                            .fill(Color.red)
                                            .frame(width: 6, height: 6)
                                        if let live = api.liveViewersByVideoId[relatedVideo.id], !live.isEmpty {
                                            Text("\(live) \(i18n.t(.watching))")
                                                .font(.system(size: 10, weight: .semibold))
                                        } else {
                                            Text(i18n.t(.liveBadge))
                                                .font(.system(size: 10, weight: .semibold))
                                                .textCase(.uppercase)
                                        }
                                    } else {
                                        let hasViews = !relatedVideo.viewCount.trimmingCharacters(in: .whitespaces).isEmpty
                                        let hasDate = !relatedVideo.publishedAt.trimmingCharacters(in: .whitespaces).isEmpty
                                        if hasViews {
                                            HStack(spacing: 3) {
                                                Image(systemName: "eye")
                                                    .font(.system(size: 9))
                                                Text(relatedVideo.viewCount)
                                            }
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                        } else {
                                            Text(" ") // zero-width placeholder keeps height
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                                .redacted(reason: .placeholder)
                                        }
                                        if hasViews && hasDate {
                                            Text("•")
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                        }
                                        if hasDate {
                                            HStack(spacing: 3) {
                                                Image(systemName: "clock")
                                                    .font(.system(size: 9))
                                                Text(relatedVideo.publishedAt)
                                            }
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 4)
                        .onAppear {
                            // EN: If live-like, fetch live viewers once for this id. TR: Canlı gibiyse, bu id için izleyici sayısını bir kez çek.
                            if isLiveLike(relatedVideo) {
                                api.fetchLiveViewersIfNeeded(videoId: relatedVideo.id)
                            }
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    // EN: Open in background tab (e.g., middle-click). TR: Arkaplanda yeni sekmede aç (ör. orta tık).
                    .overlay(MouseOpenInNewTabCatcher {
                        if let idx = tabs.indexOfTab(forVideoId: relatedVideo.id) {
                            tabs.activeTabId = tabs.tabs[idx].id
                        } else {
                            tabs.openVideoInBackground(videoId: relatedVideo.id, title: relatedVideo.title, isShorts: false)
                        }
                    })
                    .contextMenu {
                        // EN: Detect if item is a Short to build the right link. TR: Doğru linki kurmak için Short olup olmadığını saptar.
                        let isShorts = relatedVideo.title.lowercased().contains("#short") ||
                                       relatedVideo.title.lowercased().contains("#shorts") ||
                                       relatedVideo.title.lowercased().hasPrefix("shorts") ||
                                       relatedVideo.title.lowercased().contains(" shorts ") ||
                                       isUnderOneMinute(relatedVideo)
                        Button(i18n.t(.openInNewTab)) {
                            if let _ = tabs.indexOfTab(forVideoId: relatedVideo.id) {
                                // exists; keep background
                            } else {
                                tabs.openVideoInBackground(videoId: relatedVideo.id, title: relatedVideo.title, isShorts: isShorts)
                            }
                        }
                        Button(i18n.t(.copyLink)) {
                            let link = isShorts ? "https://www.youtube.com/shorts/\(relatedVideo.id)" : "https://www.youtube.com/watch?v=\(relatedVideo.id)"
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(link, forType: .string)
                        }
                        Button(i18n.t(.openInYouTube)) {
                            let link = isShorts ? "https://www.youtube.com/shorts/\(relatedVideo.id)" : "https://www.youtube.com/watch?v=\(relatedVideo.id)"
                            if let url = URL(string: link) { NSWorkspace.shared.open(url) }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Helpers
private extension RelatedVideosView {
    // EN: Live-like heuristic: API live count OR title/date keywords OR viewCount contains “watching”.
    // TR: Canlı benzeri sezgi: API canlı sayısı VEYA başlık/tarih anahtar sözcükleri VEYA viewCount “watching” içerir.
    func isLiveLike(_ v: YouTubeVideo) -> Bool {
        if let live = api.liveViewersByVideoId[v.id], !live.isEmpty { return true }
        let title = v.title.lowercased()
        let pub = v.publishedAt.lowercased()
        if title.contains(" live") || title.hasPrefix("live ") || title.contains("canlı") || title.contains(" canlı") { return true }
        if pub.contains("live") || pub.contains("canlı") || pub.contains("yayında") || pub.contains("started streaming") || pub.contains("streaming") { return true }
        let vc = v.viewCount.lowercased()
        if vc.contains("watching") || vc.contains("izleyici") { return true }
        return false
    }
}
