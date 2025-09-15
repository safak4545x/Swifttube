/*
 Overview / Genel Bakış
 EN: Main inline video player built on LightYouTubeEmbed; manages playback, seeking, ambient blur, and mini/fullscreen handoffs.
 TR: LightYouTubeEmbed üzerine kurulu ana satır içi oynatıcı; oynatma, atlama, ambient blur ve mini/tam ekran geçişlerini yönetir.
*/


// EN: SwiftUI view hosting the embed and overlays. TR: Gömülü oynatıcı ve kaplamaları barındıran SwiftUI görünümü.
import SwiftUI

// EN: Player view that wraps LightYouTubeEmbed with extra UX. TR: LightYouTubeEmbed'i ek UX ile saran oynatıcı görünüm.
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
	// EN: Optional ambient color sampling callback. TR: İsteğe bağlı ortam renk örnekleme geri çağrısı.
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
			// EN: Embed view; recreated on reloadToken (after destroy). TR: Gömülü görünüm; reloadToken ile (destroy sonrası) yeniden oluşturulur.
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
		// EN: Bottom inline controls that auto-hide on idle. TR: Boşta otomatik gizlenen alt satır içi kontroller.
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
		// EN: Track mouse activity to auto-hide controls. TR: Kontrolleri otomatik gizlemek için fare etkinliğini izle.
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
		// EN: Show PiP banner when mini player is active. TR: Mini oynatıcı aktifken PiP banner'ı göster.
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
		// EN: Show fullscreen banner while inline controls remain hidden. TR: Tam ekran banner'ı göster; satır içi kontroller gizli kalır.
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
			// EN: If no explicit start, resume from persisted progress when possible. TR: Açık bir başlangıç yoksa, mümkünse kalınan yerden devam et.
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
			// EN: Periodically persist playback progress and notify parent. TR: Oynatma ilerlemesini periyodik kaydet ve ebeveyne bildir.
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
		// EN: Forward precise time updates to parent. TR: Hassas zaman güncellemelerini ebeveyne aktar.
		.onReceive(controller.$lastKnownTime) { t in
			onTimeUpdate?(t)
		}
		.onChange(of: shouldPlay) { _, play in
			Task { @MainActor in
				if play {
					// EN: If destroyed (no webView), recreate; else just play. TR: Destroy edilmişse yeniden oluştur; değilse oynat.
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
			// EN: For a new video, load saved progress and schedule seek. TR: Yeni video için kaydı yükleyip atlamayı planla.
			Task {
				if let saved = await PlaybackProgressStore.shared.load(videoId: newId), saved > 1 {
					await MainActor.run {
						pendingSeekSeconds = saved
						seekRetryCount = 0
						attemptSeekIfPossible()
					}
				}
			}
			// EN: Restart color sampling after switching videos if enabled. TR: Video değişiminden sonra blur açıksa renk örneklemeyi yeniden başlat.
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
			// EN: Off-screen or reset request: fully stop and destroy. TR: Ekran dışı veya reset isteği: tamamen durdur ve yok et.
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
			// EN: Stop specific video when its panel closes. TR: Panel kapatılırken ilgili videoyu durdur.
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
			// EN: Requested video id not used; mini/fullscreen handle their own. TR: İstenen video id kullanılmaz; mini/tam ekran kendi içinde yönetir.
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
				// EN: If destroyed, recreate then seek when ready. TR: Destroy edilmişse yeniden yarat, hazır olunca atla.
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
				// EN: Ensure color sampling when player is ready and playing. TR: Player hazır ve oynuyorsa renk örneklemeyi garantiye al.
				if showAmbientBlur && shouldPlay { controller.startColorSampling() }
			}
		}
		.onDisappear {
			hideWorkItem?.cancel()
			progressTimer?.invalidate(); progressTimer = nil
			// EN: Safely stop/cleanup when view disappears (persist last timestamp). TR: Görünüm kapanınca güvenli durdur/temizle (son zamanı kaydet).
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
			// EN: Relay sampled colors outward (ambient UI). TR: Örneklenen renkleri dışarı aktar (ambiyans arayüz).
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
				// EN: Reschedule until idle threshold reached (guards drift). TR: Eşik dolana kadar yeniden zamanla (sapmaları önler).
				scheduleAutoHide()
			}
		}
		hideWorkItem = work
		DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
	}

	func hideImmediately() { withAnimation { showControls = false } }
	@MainActor func attemptSeekIfPossible() {
		guard let target = pendingSeekSeconds else { return }
		// EN: Retry seeking until player is ready (short backoff). TR: Player hazır olana dek atlamayı yeniden dene (kısa bekleme).
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

