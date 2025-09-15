/*
 File Overview (EN)
 Purpose: Hosts active video tabs over the page content area, enabling multi-video navigation and playlist-aware context.
 Key Responsibilities:
 - Render and manage tab items from TabCoordinator
 - Overlay tab content on top of the main page without affecting layout
 - Handle playlist context and tab activation
 Used By: MainContentView to display active tabs.

 Dosya Özeti (TR)
 Amacı: Sayfa içeriğinin üzerinde aktif video sekmelerini barındırır; çoklu video gezinmesi ve playlist bağlamı sağlar.
 Ana Sorumluluklar:
 - TabCoordinator'dan gelen sekmeleri çizmek ve yönetmek
 - Ana sayfa düzenini bozmadan içerik üstüne bindirmek
 - Playlist bağlamı ve sekme aktivasyonunu ele almak
 Nerede Kullanılır: MainContentView tarafından aktif sekmelerin gösterimi için.
*/

import SwiftUI

struct TabHostView: View {
	@ObservedObject var tabs: TabCoordinator
	@ObservedObject var youtubeAPI: YouTubeAPIService
	// When a tab becomes active, we render only the video/shorts content area
	var onCloseActive: (() -> Void)?

	var body: some View {
		Group {
			if let active = tabs.tabs.first(where: { $0.id == tabs.activeTabId }) {
				ZStack {
					switch active.kind {
					case .video(let id):
						ActiveVideoPanel(videoId: id, api: youtubeAPI, onClose: { if let id = tabs.activeTabId { tabs.close(tabId: id) } })
							.id("video-\(id)")
							.transition(.opacity.combined(with: .move(edge: .trailing)))
							.onDisappear { NotificationCenter.default.post(name: .stopVideoId, object: nil, userInfo: ["videoId": id]) }
					case .shorts(let id):
						ActiveShortsPanel(videoId: id, api: youtubeAPI, onClose: { if let id = tabs.activeTabId { tabs.close(tabId: id) } })
							.id("shorts-\(id)")
							.transition(.opacity.combined(with: .move(edge: .trailing)))
							.onDisappear { NotificationCenter.default.post(name: .shortsStopAll, object: nil) }
					}
				}
			} else {
				EmptyView()
			}
		}
		.animation(.easeInOut(duration: 0.18), value: tabs.activeTabId)
	}
}

private struct ActiveVideoPanel: View {
	let videoId: String
	@ObservedObject var api: YouTubeAPIService
	let onClose: () -> Void
	@State private var selected: YouTubeVideo? = nil
	@State private var resumeAt: Double? = nil
	@EnvironmentObject private var tabs: TabCoordinator
	// Carry playlist context from the active tab if any
	@State private var playlistContext: PlaylistContext? = nil

	var body: some View {
		GeometryReader { _ in
			if let video = selected {
				VideoDetailView(
					video: video,
					api: api,
					onClose: onClose,
					onOpenChannel: { channel in
						// No-op here; tabs manage only video panels; channel opens overlay in main content
					},
					onOpenVideo: { newVideo in
						// Update the active tab content so switching away and back keeps the chosen video
						// When a normal video is opened from related list, exit playlist mode in this tab
						playlistContext = nil
						tabs.replaceActiveTab(videoId: newVideo.id, title: newVideo.title, isShorts: false, playlist: nil)
						selected = newVideo
					},
					resumeSeconds: resumeAt,
					playlistContext: playlistContext
				)
				.id(playlistContext != nil ? "playlist-mode" : video.id)
			} else {
				ProgressView().onAppear {
					// Load resume time first, then instantiate the video so initialStartAt is populated
					Task {
						let saved = await PlaybackProgressStore.shared.load(videoId: videoId)
						await MainActor.run { resumeAt = (saved ?? 0) > 1 ? saved : nil }
						await MainActor.run {
							// Capture playlist context once when the panel becomes active
							if let active = tabs.tabs.first(where: { $0.id == tabs.activeTabId }) {
								if case .video(let vid) = active.kind, vid == videoId {
									playlistContext = active.playlist
								}
							}
							if let found = api.findVideo(by: videoId) {
								selected = found
							} else {
								// As a minimal fetch, try details to populate cache
								api.fetchVideoDetails(videoId: videoId)
								// Build a lightweight placeholder: prefer the tab's stored title if available
								let fallbackTitle = tabs.tabs.first(where: { $0.id == tabs.activeTabId })?.title ?? "Video"
								selected = YouTubeVideo(
									id: videoId,
									title: fallbackTitle,
									channelTitle: "",
									channelId: "",
									viewCount: "",
									publishedAt: "",
									thumbnailURL: youtubeThumbnailURL(videoId, quality: .mqdefault),
									description: "",
									channelThumbnailURL: "",
									likeCount: "0",
									durationText: "",
									durationSeconds: nil
								)
								// Quickly enrich basic metadata so header (title/views/date) doesn't stay empty on restore
								Task {
									do {
										let meta = try await api.fetchVideoMetadata(videoId: videoId)
										await MainActor.run {
											let enriched = YouTubeVideo(
												id: videoId,
												title: meta.title.isEmpty ? fallbackTitle : meta.title,
												channelTitle: meta.author,
												channelId: meta.channelId ?? "",
												viewCount: meta.viewCountText,
												publishedAt: meta.publishedTimeText,
												thumbnailURL: youtubeThumbnailURL(videoId, quality: .mqdefault),
												description: selected?.description ?? "",
												channelThumbnailURL: "",
												likeCount: selected?.likeCount ?? "0",
												durationText: selected?.durationText ?? "",
												durationSeconds: selected?.durationSeconds
											)
											selected = enriched
											// Update the tab title so the strip shows real title, and persist if needed
											if let idx = tabs.indexOfTab(forVideoId: videoId) {
												tabs.tabs[idx].title = enriched.title
												tabs.saveSessionIfEnabled()
											}
											// Trigger channel info and related fetches now that we have IDs/title
											if !enriched.channelId.isEmpty {
												api.fetchChannelInfo(channelId: enriched.channelId)
											}
											api.fetchRelatedVideos(videoId: enriched.id, channelId: enriched.channelId, videoTitle: enriched.title)
										}
									} catch {
										// Silent fail; placeholder remains until user activates/fetches via other paths
									}
								}
							}
						}
					}
				}
			}
		}
	}
}

private struct ActiveShortsPanel: View {
	let videoId: String
	@ObservedObject var api: YouTubeAPIService
	let onClose: () -> Void
	@State private var currentIndex: Int = 0

	var body: some View {
		HStack(spacing: 0) {
			ShortsView(
				youtubeAPI: api,
				showShortsComments: .constant(false),
				currentShortsIndex: Binding(
					get: { currentIndex },
					set: { currentIndex = $0 }
				)
			)
			.onAppear {
				if let idx = api.shortsVideos.firstIndex(where: { $0.id == videoId }) {
					currentIndex = idx
					NotificationCenter.default.post(name: .shortsFocusVideoId, object: nil, userInfo: ["videoId": videoId])
				}
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)

			// Optional right panel like comments can be added later
		}
	}
}

