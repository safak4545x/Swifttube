/*
 File Overview (EN)
 Purpose: Persist and retrieve per-video playback position and volume/mute preferences.
 Key Responsibilities:
 - Store progress keyed by videoId and update periodically
 - Read/write from disk safely; throttle writes to minimize I/O
 - Expose helpers for resume playback and Shorts volume persistence
 Used By: AudioPlaylistPlayer, mini player, ShortsRelatedService, and video views.

 Dosya Özeti (TR)
 Amacı: Video başına oynatma konumunu ve ses/kısık tercihlerinin kalıcılığını sağlamak.
 Ana Sorumluluklar:
 - videoId anahtarıyla ilerlemeyi saklamak ve periyodik güncellemek
 - Diske güvenli okuma/yazma; I/O'yu azaltmak için yazımları sınırla
 - Devam oynatma ve Shorts ses kalıcılığı için yardımcılar sunmak
 Nerede Kullanılır: AudioPlaylistPlayer, mini oynatıcı, ShortsRelatedService ve video görünümleri.
*/

import Foundation

// Persist last watched second for a given videoId, using the existing Json cache infra.
// Long TTL so users can come back much later and continue where they left.
actor PlaybackProgressStore {
	static let shared = PlaybackProgressStore()

	private let ttl: TimeInterval = CacheTTL.sevenDays * 26 // ~6 months

	private func key(for videoId: String) -> CacheKey {
		CacheKey("progress:video:\(videoId)")
	}

	/// Load last watched position in seconds for a video, if any.
	func load(videoId: String) async -> Double? {
		await GlobalCaches.json.get(key: key(for: videoId), type: Double.self)
	}

	/// Save the current watched position (in seconds) for a video.
	/// Positions less than or equal to 1s are treated as "reset" and remove persisted progress.
	func save(videoId: String, seconds: Double) async {
		guard seconds > 1 else {
			await clear(videoId: videoId)
			return
		}
		await GlobalCaches.json.set(key: key(for: videoId), value: seconds, ttl: ttl)
	}

	/// Clear persisted progress for a specific video.
	func clear(videoId: String) async {
		// Overwrite with 0 so it naturally expires soon; or we could delete by writing an already-expired envelope.
		// Using a tiny ttl to effectively drop it on next read.
		await GlobalCaches.json.set(key: key(for: videoId), value: 0.0, ttl: 1)
	}
}

