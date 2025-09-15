/*
 File Overview (EN)
 Purpose: Right-hand related videos list under a playing video; supports local fetching, lazy loads, and quick actions.
 Key Responsibilities:
 - Render related items with skeletons and incremental updates
 - Allow open-in-new-tab, copy link, open channel actions
 - Integrate with Shorts-related service when the current video is a Short
 Used By: Video detail pages.

 Dosya Özeti (TR)
 Amacı: Oynatılan videonun yanında sağ tarafta ilgili videolar listesi; yerel çekim, tembel yükleme ve hızlı eylemler.
 Ana Sorumluluklar:
 - İlgili öğeleri iskeletler ve kademeli güncellemelerle göstermek
 - Yeni sekmede aç, bağlantıyı kopyala, kanalı aç eylemlerini sağlamak
 - Geçerli video Short ise Shorts-related servis ile entegrasyon
 Nerede Kullanılır: Video detay sayfaları.
*/

import SwiftUI
import AppKit

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
            Text(i18n.t(.recommendedVideosTitle))
                .font(.headline)
                .padding(.bottom, 4)

            if api.relatedVideos.isEmpty {
                if api.isLoadingRelated {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(i18n.t(.recommendedLoading))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
                } else {
                    Text(i18n.t(.recommendedNone))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                }
            } else {
                // Sadece gerçek başlığa sahip videoları göster (title!=id ve boş değil)
                let displayable = api.relatedVideos.filter { !$0.title.isEmpty && $0.title != $0.id }
                ForEach(displayable.prefix(8)) { relatedVideo in
                    Button(action: {
                        onSelect?(relatedVideo)
                    }) {
                        HStack(spacing: 8) {
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
                                // Başlık: eğer API başlık döndürememişse (title==id) kullanıcıya id göstermeyelim
                                Text(relatedVideo.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .lineLimit(2)

                                HStack(alignment: .center, spacing: 6) {
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

                                // Meta satırı: canlı ise izleyici sayısını göster; değilse gelen views + tarih
                                HStack(spacing: 4) {
                                    if isLiveLike(relatedVideo) {
                                        // Küçük kırmızı nokta + izleyici sayısı (varsa)
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
                            // Canlı gibi görünüyorsa izleyici sayısını tek seferlik çek
                            if isLiveLike(relatedVideo) {
                                api.fetchLiveViewersIfNeeded(videoId: relatedVideo.id)
                            }
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .overlay(MouseOpenInNewTabCatcher {
                        if let idx = tabs.indexOfTab(forVideoId: relatedVideo.id) {
                            tabs.activeTabId = tabs.tabs[idx].id
                        } else {
                            tabs.openVideoInBackground(videoId: relatedVideo.id, title: relatedVideo.title, isShorts: false)
                        }
                    })
                    .contextMenu {
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
    func isLiveLike(_ v: YouTubeVideo) -> Bool {
        // 1) API daha önce canlı izleyici sayısı doldurduysa kesin canlı say.
        if let live = api.liveViewersByVideoId[v.id], !live.isEmpty { return true }
        // 2) Başlık/publishedAt ipuçları
        let title = v.title.lowercased()
        let pub = v.publishedAt.lowercased()
        if title.contains(" live") || title.hasPrefix("live ") || title.contains("canlı") || title.contains(" canlı") { return true }
        if pub.contains("live") || pub.contains("canlı") || pub.contains("yayında") || pub.contains("started streaming") || pub.contains("streaming") { return true }
        // 3) Views alanı "watching" içeriyorsa
        let vc = v.viewCount.lowercased()
        if vc.contains("watching") || vc.contains("izleyici") { return true }
        return false
    }
}
