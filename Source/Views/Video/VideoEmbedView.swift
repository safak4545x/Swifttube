/*
 File Overview (EN)
 Purpose: Main in-tab video player built on LightYouTubeEmbed; handles play/pause, seek, ambient blur, and inline/mini/fullscreen transitions.
 Key Responsibilities:
 - Control playback and time updates; route events to mini/fullscreen windows
 - Manage overlay controls visibility with mouse inactivity heuristics
 - Support color sampling for ambient UI and safe destroy/recreate cycles
 Used By: Video detail pages and overlay player with shared state.

 Dosya Özeti (TR)
 Amacı: LightYouTubeEmbed tabanlı ana sekme içi oynatıcı; oynat/duraklat, ileri/geri sarma, ambient blur ve mini/tam ekran geçişleri.
 Ana Sorumluluklar:
 - Oynatma ve zaman güncellemelerini yönetmek; olayları mini/tam ekran pencerelerine yönlendirmek
 - Fare hareketsizliği sezgileri ile kaplama kontrollerinin görünürlüğünü yönetmek
 - Ortam rengi örneklemeyi ve güvenli yok et/yeniden oluştur döngülerini desteklemek
 Nerede Kullanılır: Video detay sayfaları ve ortak durumlu overlay oynatıcı.
*/


import SwiftUI

// LightYouTubeEmbed tabanlı yeni VideoEmbedView
struct VideoEmbedView: View {
	@EnvironmentObject var i18n: Localizer
	let videoId: String
	@Binding var shouldPlay: Bool
	// Toggle for ambient blurred background around the player (controlled by parent)
	@Binding var showAmbientBlur: Bool
	// Parent can observe fine-grained time updates (used to transfer exact timestamp to mini player)
	var onTimeUpdate: ((Double) -> Void)? = nil
	@StateObject private var controller = LightYouTubeController()
	@State private var isReady = false
	@State private var reloadToken = UUID() // force recreate after destroy
	@State private var pendingSeekSeconds: Double? = nil
	@State private var seekRetryCount = 0
	@State private var progressTimer: Timer? = nil
	// Fullscreen artık ayrı bir overlay window ile yönetilecek
	@State private var inlineWasPlaying = false
	// Mini (PiP) aktifken göstermek için durum bayrağı
	@State private var isInMiniPlayer = false
	// Tamekrandan dönüşte başlangıç saniyesini doğrudan player'a geçirmek için
	@State private var relaunchStartSeconds: Double = 0
	// Overlay kontrol görünürlüğü (mouse hareketsiz 3sn -> gizle, çıkınca gizle)
	@State private var showControls = true
	@State private var lastMouseActivityAt = Date()
	@State private var hideWorkItem: DispatchWorkItem? = nil

	#if canImport(AppKit)
	private var isFullscreenForThisVideo: Bool {
		if FullscreenPlayerWindow.shared.isPresented,
		   FullscreenPlayerWindow.shared.activeVideoId == videoId {
			return true
		}
		return false
	}
	#else
	private var isFullscreenForThisVideo: Bool { false }
	#endif

	// Dışarıya dinamik renk yayınlamak için (opsiyonel)
	var onColorSampled: ((NSColor) -> Void)? = nil

	init(videoId: String, shouldPlay: Binding<Bool>, showAmbientBlur: Binding<Bool>, initialStartAt: Double? = nil, onColorSampled: ((NSColor) -> Void)? = nil, onTimeUpdate: ((Double) -> Void)? = nil) {
		self.videoId = videoId
		self._shouldPlay = shouldPlay
		self._showAmbientBlur = showAmbientBlur
		self.onColorSampled = onColorSampled
		self.onTimeUpdate = onTimeUpdate
		if let s = initialStartAt, s > 0 {
			self._relaunchStartSeconds = State(initialValue: s)
		}
	}

	var body: some View {
		ZStack {
			// Recreated when reloadToken changes (after destroy of off-screen players)
			LightYouTubeEmbed(
				videoId: videoId,
				startSeconds: relaunchStartSeconds,
				autoplay: shouldPlay,
				forceHideAll: false,
				showOnlyProgressBar: false,
				applyAppearanceSettings: true,
				enableColorSampling: showAmbientBlur,
				controller: controller,
				onReady: { withAnimation(.easeOut(duration: 0.18)) { isReady = true } }
			)
			.id(reloadToken)
			.clipShape(RoundedRectangle(cornerRadius: 12))

			if !isReady {
				Color.black
					.transition(.opacity)
					.overlay(ProgressView().scaleEffect(1.05))
			}
		}
		// Alt-orta kontrol butonları (idle/exit ile otomatik gizlenir)
		.overlay(alignment: .bottom) {
			if !isInMiniPlayer && !isFullscreenForThisVideo {
						HStack(spacing: 12) {
				// Mini pencere (PiP benzeri) butonu - sol
				Button {
					controller.currentTime { secs in
						let startAt = (secs > 0 ? secs : controller.lastKnownTime)
						shouldPlay = false
						controller.pause()
						controller.destroy()
						isReady = false
						// PiP başladı bilgisi
						isInMiniPlayer = true
						showControls = false
						#if canImport(AppKit)
						MiniPlayerWindow.shared.present(videoId: videoId, startAt: startAt) { returned in
							// PiP kapandı
							isInMiniPlayer = false
							let resumeAt = returned ?? startAt
							isReady = false
							relaunchStartSeconds = resumeAt
							if inlineWasPlaying { shouldPlay = true }
							reloadToken = UUID()
							DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
								pendingSeekSeconds = resumeAt
								seekRetryCount = 0
								if inlineWasPlaying { shouldPlay = true }
								attemptSeekIfPossible()
							}
							DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { relaunchStartSeconds = 0 }
						}
						#endif
					}
				} label: {
					Image(systemName: "pip.enter")
						.font(.system(size: 15, weight: .semibold))
						.foregroundStyle(.white)
				}
				.buttonStyle(.plain)

				// Ortadaki: Ambient blur toggle (Shorts benzeri arkaplan)
				Button {
					withAnimation(.easeInOut(duration: 0.18)) { showAmbientBlur.toggle() }
				} label: {
					Image(systemName: showAmbientBlur ? "lightbulb.fill" : "lightbulb")
						.font(.system(size: 15, weight: .semibold))
						.foregroundStyle(.white)
				}
				.buttonStyle(.plain)

				// Tam ekran butonu - sağ
				Button {
				// Uygulama değil, sadece video tam ekran olsun
				inlineWasPlaying = shouldPlay
				controller.currentTime { secs in
					let startAt = (secs > 0 ? secs : controller.lastKnownTime)
					shouldPlay = false // inline player kesin dursun
					controller.pause()
					controller.destroy() // kaynak tüketimi sıfırlansın
					isReady = false
					#if canImport(AppKit)
					FullscreenPlayerWindow.shared.present(videoId: videoId, startAt: startAt) { returned in
						// Kapatınca inline player'ı temiz bir şekilde yeniden yarat ve zamanı geri yükle
						let resumeAt = returned ?? startAt
						isReady = false
						// Başlangıç saniyesini doğrudan webview'e ver ve gerekiyorsa otomatik oynat
						relaunchStartSeconds = resumeAt
						if inlineWasPlaying { shouldPlay = true }
						reloadToken = UUID()
						DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
							pendingSeekSeconds = resumeAt
							seekRetryCount = 0
							if inlineWasPlaying { shouldPlay = true }
							// Player hazır ise hemen uygula; değilse attemptSeekIfPossible kendi yeniden deneyecek
							attemptSeekIfPossible()
						}
						// Biraz sonra sıfırla; yeni videolar 0'dan başlasın
						DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { relaunchStartSeconds = 0 }
					}
					#endif
				}
			} label: {
				Image(systemName: "arrow.up.left.and.arrow.down.right")
					.font(.system(size: 16, weight: .bold))
					.foregroundStyle(.white)
			}
			.buttonStyle(.plain)
			}
			.padding(.horizontal, 10)
			.padding(.vertical, 8)
			.background(.ultraThinMaterial, in: Capsule())
			.shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 2)
			.padding(.bottom, 4)
			.padding(.horizontal, 2)
			.transition(.move(edge: .bottom).combined(with: .opacity))
			.animation(.easeInOut(duration: 0.22), value: showControls)
			.opacity(showControls ? 1 : 0)
			.offset(y: showControls ? 0 : 24)
			}
		}
		// Mouse etkinliklerini dinle ve otomatik gizleme zamanlayıcısını yönet
		.overlay {
			MouseActivityView { event in
				switch event {
				case .entered, .moved:
					lastMouseActivityAt = Date()
					if !showControls { withAnimation { showControls = true } }
					scheduleAutoHide()
				case .exited:
					hideImmediately()
				}
			}
			.allowsHitTesting(false) // Görünmez katman; tıklamayı engellemesin
		}
		// PiP aktifken üst katmanda banner göster (spinner'ın da üstünde)
		.overlay {
			if isInMiniPlayer {
				ZStack {
					Color.black.opacity(0.28)
					VStack(spacing: 10) {
						HStack(spacing: 8) {
							Image(systemName: "pip")
								.font(.system(size: 14, weight: .semibold))
							Text(i18n.t(.pipModeBanner))
								.font(.system(size: 14, weight: .semibold))
						}
						.foregroundStyle(.white)
						.padding(.horizontal, 12)
						.padding(.vertical, 8)
						.background(.ultraThinMaterial, in: Capsule())
					}
				}
				.transition(.opacity)
				.allowsHitTesting(false)
			}
		}
		// Fullscreen aktifken normal panelde banner göster ve alt kontroller zaten gizlendi
		.overlay {
			if isFullscreenForThisVideo {
				ZStack {
					Color.black.opacity(0.28)
					VStack(spacing: 10) {
						HStack(spacing: 8) {
							Image(systemName: "arrow.up.left.and.arrow.down.right")
								.font(.system(size: 14, weight: .semibold))
							Text(i18n.t(.fullscreenModeBanner))
								.font(.system(size: 14, weight: .semibold))
						}
						.foregroundStyle(.white)
						.padding(.horizontal, 12)
						.padding(.vertical, 8)
						.background(.ultraThinMaterial, in: Capsule())
					}
				}
				.transition(.opacity)
				.allowsHitTesting(false)
			}
		}
		.onAppear {
			// If no explicit start was provided (e.g., from fullscreen/miniplayer return), try resuming from persisted progress
			Task {
				if relaunchStartSeconds <= 0 {
					if let saved = await PlaybackProgressStore.shared.load(videoId: videoId), saved > 1 {
						await MainActor.run {
							pendingSeekSeconds = saved
							seekRetryCount = 0
							attemptSeekIfPossible()
						}
					}
				}
			}
			// Start periodic progress writes while the view is visible
			progressTimer?.invalidate()
			progressTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
				Task { @MainActor in
					controller.currentTime { t in
						let time = (t > 0 ? t : controller.lastKnownTime)
						Task { await PlaybackProgressStore.shared.save(videoId: videoId, seconds: time) }
						onTimeUpdate?(time)
					}
				}
			}
		}
		// Push fine-grained time updates to parent as the embed reports them
		.onReceive(controller.$lastKnownTime) { t in
			onTimeUpdate?(t)
		}
		.onChange(of: shouldPlay) { _, play in
			Task { @MainActor in
				if play {
					// Eğer destroy edilmişse (webView yok) yeniden yarat
					if controller.isDestroyed {
						isReady = false
						reloadToken = UUID()
						// play isteği LightYouTubeEmbed içindeki autoplay ile gerçekleşecek
					} else {
						controller.play()
					}
				} else {
					controller.pause()
				}
			}
		}
		.onChange(of: videoId) { _, newId in
			isReady = false
			relaunchStartSeconds = 0
			// Load saved progress for the new video and schedule a seek
			Task {
				if let saved = await PlaybackProgressStore.shared.load(videoId: newId), saved > 1 {
					await MainActor.run {
						pendingSeekSeconds = saved
						seekRetryCount = 0
						attemptSeekIfPossible()
					}
				}
			}
			// Yeni videoya geçildiğinde renk sampling'i yeniden başlat (ampul açıksa)
			if showAmbientBlur {
				Task { @MainActor in
					// Eski timer'ı temizle ve yeni player yüklenmesine küçük bir gecikmeyle fırsat ver
					controller.stopColorSampling()
					DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
						// Hala ilgili görünüm ve blur açık ise başlat
						if showAmbientBlur { controller.startColorSampling() }
					}
				}
			}
		}
		.onReceive(NotificationCenter.default.publisher(for: .shortsResetVideoId)) { note in
			guard let target = note.userInfo?["videoId"] as? String, target == videoId else { return }
			// Off-screen veya reset istenen video: tamamen durdur ve destroy et
			Task { @MainActor in
				controller.pause()
				controller.destroy()
			}
		}
		.onReceive(NotificationCenter.default.publisher(for: .shortsStopAll)) { _ in
			Task { @MainActor in
				controller.pause()
				controller.destroy()
			}
		}
		// Normal video panel kapatılırken spesifik videoyu durdur
		.onReceive(NotificationCenter.default.publisher(for: .stopVideoId)) { note in
			guard let target = note.userInfo?["videoId"] as? String, target == videoId else { return }
			Task { @MainActor in
				controller.pause()
				controller.destroy()
			}
		}
		// Yorum / açıklama timestamp tıklanınca atlama
		.onReceive(NotificationCenter.default.publisher(for: .seekToSeconds)) { note in
			guard let secs = note.userInfo?["seconds"] as? Int else { return }
			// let requestedVideoId = note.userInfo?["videoId"] as? String // not used here; MiniPlayer handles its own
			#if canImport(AppKit)
			// PiP açıkken inline player seek etmesin; MiniPlayerContent kendi içinde dinleyip uygular
			if MiniPlayerWindow.shared.isPresented { return }
			// Fullscreen açık ve bu videoya aitse, inline seek etme (tam ekran player dinleyip uygular)
			if FullscreenPlayerWindow.shared.isPresented,
			   FullscreenPlayerWindow.shared.activeVideoId == videoId { return }
			#endif
			Task { @MainActor in
				let target = Double(secs)
				pendingSeekSeconds = target
				seekRetryCount = 0
				// Destroy edilmişse yeniden yarat sonra hazır olunca atla
				if controller.isDestroyed {
					isReady = false
					reloadToken = UUID()
				}
				attemptSeekIfPossible()
			}
		}
		.onChange(of: isReady) { _, newVal in
			if newVal {
				attemptSeekIfPossible()
				// Player hazır olduğunda ve oynatılacaksa sampling'i garantiye al
				if showAmbientBlur && shouldPlay { controller.startColorSampling() }
			}
		}
		.onDisappear {
			hideWorkItem?.cancel()
			progressTimer?.invalidate(); progressTimer = nil
			// View sahneden kalkınca güvenli şekilde durdur/temizle
			Task { @MainActor in
				// Save one last time before destroying if we can read a timestamp
				controller.currentTime { t in
					let time = (t > 0 ? t : controller.lastKnownTime)
					Task { await PlaybackProgressStore.shared.save(videoId: videoId, seconds: time) }
				}
				controller.pause()
				controller.destroy()
			}
		}
		.onChange(of: showAmbientBlur) { _, enabled in
			Task { @MainActor in
				if enabled {
					if shouldPlay { controller.startColorSampling() }
				} else {
					controller.stopColorSampling()
				}
			}
		}
		// Controller'ın yayımladığı renkleri yakala ve dışarı ile paylaş
		.onReceive(controller.$sampledColor.removeDuplicates { lhs, rhs in
			if let l = lhs, let r = rhs { return l == r }
			return lhs == nil && rhs == nil
		}) { color in
			if let c = color { onColorSampled?(c) }
		}
	}
}

private extension VideoEmbedView {
	func scheduleAutoHide() {
		hideWorkItem?.cancel()
		let work = DispatchWorkItem { [lastMouseActivityAt] in
			let elapsed = Date().timeIntervalSince(lastMouseActivityAt)
			if elapsed >= 3.0 {
				withAnimation { showControls = false }
			} else {
				// Bekleme süresi dolmamışsa yeniden zamanla (drift'e karşı)
				scheduleAutoHide()
			}
		}
		hideWorkItem = work
		DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
	}

	func hideImmediately() { withAnimation { showControls = false } }
	@MainActor func attemptSeekIfPossible() {
		guard let target = pendingSeekSeconds else { return }
		// Player hazır değilse yeniden dene (en fazla 10 deneme ~2s)
		if !isReady || controller.isDestroyed {
			if seekRetryCount < 25 {
				seekRetryCount += 1
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { attemptSeekIfPossible() }
			}
			return
		}
		controller.seek(to: target)
		if shouldPlay {
			controller.play()
		} else {
			controller.pause()
		}
		pendingSeekSeconds = nil
	}
}

// Eski overlay kaldırıldı; tam ekran artık ayrı pencerede.

