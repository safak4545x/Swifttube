/*
 Overview / Genel Bakış
 EN: Hosts the active tab as an overlay (video or shorts) with playlist context handling.
 TR: Aktif sekmeyi (video veya shorts) üstte barındırır; oynatma listesi bağlamını yönetir.
*/

// EN: SwiftUI for overlaying active tab content. TR: Aktif sekme içeriğini üstte göstermek için SwiftUI.
import SwiftUI

// EN: Renders active tab panel driven by TabCoordinator. TR: TabCoordinator tarafından yönlendirilen aktif paneli çizer.
struct TabHostView: View {
	@ObservedObject var tabs: TabCoordinator
	@ObservedObject var youtubeAPI: YouTubeAPIService
	// EN: Render only the video/shorts content of the active tab. TR: Aktif sekmenin sadece video/shorts alanını çiz.
	var onCloseActive: (() -> Void)?

	var body: some View {
		Group {
			if let active = tabs.tabs.first(where: { $0.id == tabs.activeTabId }) {
				ZStack {
					switch active.kind {
					case .video(let id):
						// EN: Video detail overlay; closing removes the tab. TR: Video detay katmanı; kapatınca sekmeyi kaldırır.
						ActiveVideoPanel(videoId: id, api: youtubeAPI, onClose: { if let id = tabs.activeTabId { tabs.close(tabId: id) } })
							.id("video-\(id)")
							.transition(.opacity.combined(with: .move(edge: .trailing)))
							.onDisappear { NotificationCenter.default.post(name: .stopVideoId, object: nil, userInfo: ["videoId": id]) }
					case .shorts(let id):
						// EN: Shorts vertical swiper; closing removes the tab. TR: Shorts dikey kaydırıcı; kapatınca sekmeyi kaldırır.
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

// EN: Video detail panel bound to a specific video id. TR: Belirli bir video id'sine bağlı video detay paneli.
private struct ActiveVideoPanel: View {
	let videoId: String
	@ObservedObject var api: YouTubeAPIService
	let onClose: () -> Void
	@State private var selected: YouTubeVideo? = nil
	@State private var resumeAt: Double? = nil
	@EnvironmentObject private var tabs: TabCoordinator
	// EN: Playlist context carried from the active tab. TR: Aktif sekmeden taşınan oynatma listesi bağlamı.
	@State private var playlistContext: PlaylistContext? = nil

	var body: some View {
		GeometryReader { _ in
			if let video = selected {
				VideoDetailView(
					video: video,
					api: api,
					onClose: onClose,
					onOpenChannel: { channel in
						// EN: No-op; channels open from main content overlays. TR: İşlem yok; kanallar ana içerik katmanından açılır.
					},
					onOpenVideo: { newVideo in
						// EN: Replace active tab content with selected related video; exit playlist mode.
						// TR: Aktif sekme içeriğini seçilen ilgili video ile değiştir; playlist modundan çık.
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
					// EN: Load resume time then instantiate video to pass initialStartAt. TR: Devam zamanını yükle, sonra initialStartAt vermek için videoyu oluştur.
					Task {
						let saved = await PlaybackProgressStore.shared.load(videoId: videoId)
						await MainActor.run { resumeAt = (saved ?? 0) > 1 ? saved : nil }
						await MainActor.run {
							// EN: Capture playlist context once when panel becomes active. TR: Panel aktif olduğunda playlist bağlamını bir kez yakala.
							if let active = tabs.tabs.first(where: { $0.id == tabs.activeTabId }) {
								if case .video(let vid) = active.kind, vid == videoId {
									playlistContext = active.playlist
								}
							}
							if let found = api.findVideo(by: videoId) {
								selected = found
							} else {
								// EN: Minimal fetch to warm cache with details. TR: Detaylarla önbelleği ısıtmak için minimal fetch.
								api.fetchVideoDetails(videoId: videoId)
								// EN: Build placeholder; prefer stored tab title if any. TR: Placeholder oluştur; varsa sekme başlığını kullan.
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
								// EN: Enrich header fields (title/views/date) quickly after restore. TR: Geri yüklemeden sonra başlık alanlarını hızla zenginleştir.
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

// EN: Shorts panel embedding ShortsView with current index tracking. TR: ShortsView'u gömen ve geçerli indeksi takip eden Shorts paneli.
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

			// EN: Optional right panel (e.g., comments) can be added later. TR: İsteğe bağlı sağ panel (yorumlar vb.) daha sonra eklenebilir.
		}
	}
}

