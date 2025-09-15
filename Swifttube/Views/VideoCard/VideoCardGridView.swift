/*
 Overview / Genel Bakış
 EN: Responsive video card layout with badges and context menu.
 TR: Rozetler ve bağlam menülü duyarlı video kart yerleşimi.
*/

import SwiftUI
import AppKit

// Video Card Grid View - Responsive
struct VideoCardGridView: View {
    @EnvironmentObject var i18n: Localizer
    @EnvironmentObject private var tabs: TabCoordinator
    let video: YouTubeVideo
    var onTap: (() -> Void)? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                    CachedAsyncImage(url: URL(string: video.thumbnailURL)) { image in
                    image.resizable()
                        .aspectRatio(16/9, contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .shimmering()
                }
                .clipped()
                .cornerRadius(12)
                // Match home card border
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.15), lineWidth: 2)
                )

                // EN: Duration badge (hidden for live/shorts). TR: Süre rozeti (canlı/shorts için gizlenir).
                if showDurationBadge {
                    VStack {
                        HStack {
                            Spacer()
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
                        .padding(.top, 8)
                        .padding(.trailing, 8)
                        Spacer()
                    }
                }

                VStack {
                    Spacer()
                    HStack {
                        Text(video.title)
                            .font(.headline)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .foregroundColor(.primary)
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(.ultraThinMaterial)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                    .padding(8)
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "eye")
                        Text(video.viewCount)
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                        Text(video.publishedAt)
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 4)
        }
        // Harici gri arka planı engellemek için hiçbir ekstra background/karte stili eklenmiyor
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        .contextMenu {
            Button(i18n.t(.openInNewTab)) {
                if let _ = tabs.indexOfTab(forVideoId: video.id) {
                    // already exists; keep in background
                } else {
                    tabs.openVideoInBackground(videoId: video.id, title: video.title, isShorts: isShortsLikely)
                }
            }
            Button(i18n.t(.copyLink)) {
                let link = isShortsLikely ? "https://www.youtube.com/shorts/\(video.id)" : "https://www.youtube.com/watch?v=\(video.id)"
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(link, forType: .string)
            }
            Button(i18n.t(.openInYouTube)) {
                let link = isShortsLikely ? "https://www.youtube.com/shorts/\(video.id)" : "https://www.youtube.com/watch?v=\(video.id)" // EN: Respect shorts vs regular link. TR: Shorts/normal bağlantıya göre seç.
                if let url = URL(string: link) { NSWorkspace.shared.open(url) }
            }
        }
    }
}

// MARK: - Helpers
private extension VideoCardGridView {
    var isShortsLikely: Bool {
        let lower = video.title.lowercased()
        if lower.contains("#short") || lower.contains("#shorts") || lower.contains(" shorts ") || lower.hasPrefix("shorts") {
            return true
        }
        return isUnderOneMinute(video) // EN: Fallback to duration <= 60s. TR: Yedek koşul: süre <= 60sn.
    }
    var isLiveLike: Bool {
        // Heuristic similar to VideoCardView
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
        if vc.isEmpty || pub.isEmpty { return true }
        return false
    }

    var showDurationBadge: Bool {
        guard !isLiveLike else { return false }
        guard !video.durationText.isEmpty else { return false }
        // Hide for Shorts (#shorts in title or very short duration)
        let lower = video.title.lowercased()
        if lower.contains("#short") || lower.contains("#shorts") || lower.contains(" shorts ") || lower.hasPrefix("shorts") {
            return false
        }
        if let secs = video.durationSeconds, secs <= 65 { return false }
        return true
    }
}
