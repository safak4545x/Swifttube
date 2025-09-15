/*
 File Overview (EN)
 Purpose: Mini audio player for playlists or single videos, backed by a hidden LightYouTubeController.
 Key Responsibilities:
 - Maintain queue, playback state, shuffle/repeat modes, and progress/volume
 - Start from playlist context or single video; observe cache updates to refresh metadata
 - Expose controls for play/pause/next/previous/seek and handle auto-advance
 Used By: HiddenAudioPlayerView and bottom player bar UI.

 Dosya Özeti (TR)
 Amacı: Gizli LightYouTubeController ile çalınan mini ses oynatıcı (playlist veya tek video).
 Ana Sorumluluklar:
 - Kuyruk, oynatma durumu, karıştır/tekrar modları ile ilerleme/ses durumunu yönetmek
 - Playlist bağlamından veya tek videodan başlatmak; önbellek güncellemelerini izleyip metadataları tazelemek
 - Oynat/duraklat/ileri/geri/arama gibi kontrolleri sunmak ve otomatik ilerlemeyi ele almak
 Nerede Kullanılır: HiddenAudioPlayerView ve alt oynatıcı çubuğu arayüzü.
*/

import Foundation
import Combine

/// Simple audio-only playlist player backed by LightYouTubeController.
/// Owns a hidden webview player and advances to next video when current ends.
@MainActor
final class AudioPlaylistPlayer: ObservableObject {
    @Published var isActive: Bool = false
    @Published var isPlaying: Bool = false
    @Published var currentVideoId: String? = nil
    @Published var currentVideo: YouTubeVideo? = nil
    @Published var currentIndex: Int = 0
    @Published var queue: [String] = []
    @Published var queueVideos: [YouTubeVideo] = []
    // The currently active playlist id (read-only outside). Used by UI (e.g., popovers) to fetch more items.
    @Published private(set) var activePlaylistId: String? = nil

    // Expose controller to be consumed by HiddenAudioPlayerView
    let controller = LightYouTubeController()

    private var cancellables: Set<AnyCancellable> = []
    // Dedicated subscription for playlist cache updates (so we can replace it per start)
    private var playlistCacheCancellable: AnyCancellable? = nil
    // Apply an initial seek when the player becomes ready
    private var pendingInitialSeek: Double? = nil
    // Time tracking
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    private var durationTimer: Timer?
    // Volume (0.0 - 1.0)
    @Published var volume: Double = 0.8
    // Shuffle mode: when enabled, Next picks a random item
    @Published var isShuffleEnabled: Bool = false {
        didSet {
            if isShuffleEnabled { repeatMode = .off }
        }
    }
    // Repeat modes: off, repeat once, repeat infinitely
    enum RepeatMode: Equatable {
        case off
        case once
        case infinite
    }
    @Published var repeatMode: RepeatMode = .off {
        didSet {
            if repeatMode != .off { isShuffleEnabled = false }
        }
    }

    // Track how this mini player session was launched
    enum LaunchOrigin {
        case unknown
        case videoPanel
        case other
    }
    @Published var launchOrigin: LaunchOrigin = .unknown

    // Convenience to set modes programmatically while preserving exclusivity
    func setShuffle(_ on: Bool) {
        isShuffleEnabled = on
        if on { repeatMode = .off }
    }
    /// Cycle repeat mode: Off -> Once -> Infinite -> Off
    func cycleRepeatMode() {
        switch repeatMode {
        case .off:
            repeatMode = .once
        case .once:
            repeatMode = .infinite
        case .infinite:
            repeatMode = .off
        }
    }
    // Prevent repeated triggers at the very end while time oscillates
    private var repeatArm: Bool = true
    // The API instance this player was started with; used by UI helpers to request more items on the same cache
    private(set) var boundAPI: YouTubeAPIService? = nil

    init() {
        // Advance to next when state becomes 0 (ended)
        controller.$playerState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self else { return }
                // Some flows report paused (2) at the very end instead of ended (0). Treat it as ended if we're at tail.
                let nearEnd = (self.duration > 2) && (self.currentTime >= max(0, self.duration - 0.6))
                if state == 0 || (state == 2 && nearEnd) { // ended (or effectively ended)
                    switch self.repeatMode {
                    case .off:
                        self.next()
                    case .once:
                        // Replay once, then go back to off
                        if let id = self.currentVideoId, !id.isEmpty {
                            self.replayCurrentFromStart()
                            self.repeatMode = .off
                        } else {
                            self.next()
                        }
                    case .infinite:
                        // Always replay from start
                        if let id = self.currentVideoId, !id.isEmpty {
                            self.replayCurrentFromStart()
                        } else {
                            self.next()
                        }
                    }
                }
            }
            .store(in: &cancellables)

        // Mirror last known time from controller
        controller.$lastKnownTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] t in
                guard let self = self else { return }
                self.currentTime = t
                // Arm repeat when we're clearly before the tail
                if self.duration > 2, t < self.duration - 1.2 { self.repeatArm = true }
                // Fallback: if repeat is active and we cross into the tail window, auto-replay even if 'ended' didn't arrive
                if self.repeatArm,
                   self.duration > 2,
                   t >= max(0, self.duration - 0.4) {
                    switch self.repeatMode {
                    case .off:
                        break
                    case .once:
                        self.repeatArm = false
                        self.replayCurrentFromStart()
                        self.repeatMode = .off
                    case .infinite:
                        self.repeatArm = false
                        self.replayCurrentFromStart()
                    }
                }
            }
            .store(in: &cancellables)

        controller.$duration
            .receive(on: DispatchQueue.main)
            .sink { [weak self] d in self?.duration = d }
            .store(in: &cancellables)

        // Whenever player state changes, try to apply a pending initial seek (first time only)
        controller.$playerState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyPendingInitialSeekIfPossible() }
            .store(in: &cancellables)
    }

    private func replayCurrentFromStart() {
        // Reset UI progress to 0 and command the player to seek+play
        currentTime = 0
        isPlaying = true
        repeatArm = false
        controller.seek(to: 0)
        // Keep duration as-is; the bar will stay accurate. If needed, we could re-fetch:
        // controller.fetchDuration { _ in }
    }

    func start(playlistId: String, startIndex: Int? = nil, using api: YouTubeAPIService, startAtSeconds: Double? = nil, origin: LaunchOrigin = .other) {
        Task { @MainActor in
            self.boundAPI = api
            self.activePlaylistId = playlistId
            self.pendingInitialSeek = startAtSeconds
            self.launchOrigin = origin
            var items = api.cachedPlaylistVideos[playlistId] ?? []
            // If no real items are present yet, proactively load a larger prefix so the queue is populated without opening PlaylistView
            if items.filter({ !($0.title.isEmpty && $0.channelTitle.isEmpty) }).isEmpty,
               let p = api.userPlaylists.first(where: { $0.id == playlistId }) {
                await api.ensurePlaylistLoadedCount(playlist: p, minCount: 40)
                items = api.cachedPlaylistVideos[playlistId] ?? []
            }
            // Build a queue from cached playlist items, skipping placeholders
            let real: [YouTubeVideo] = items.filter { !($0.title.isEmpty && $0.channelTitle.isEmpty) }
            let ids = real.map { $0.id }.filter { !$0.isEmpty }
            guard !ids.isEmpty else { return }

            self.queue = ids
            self.queueVideos = real
            let index = min(max(startIndex ?? 0, 0), ids.count - 1)
            self.currentIndex = index
            self.currentVideoId = ids[index]
            self.currentVideo = real[index]
            self.isActive = true
            self.isPlaying = true
            // Ensure bar visible
            NotificationCenter.default.post(name: .showBottomPlayerBar, object: nil)

            // Kick an initial duration fetch to populate quickly
            self.controller.fetchDuration { _ in }
            // Try to apply initial seek when the player is ready
            self.applyPendingInitialSeekIfPossible()

            // Observe future enrichments and refresh queue + current video metadata when playlist cache changes
            playlistCacheCancellable?.cancel()
            playlistCacheCancellable = api.$cachedPlaylistVideos
                .receive(on: DispatchQueue.main)
                .sink { [weak self] dict in
                    guard let self = self, let pid = self.activePlaylistId else { return }
                    guard let list = dict[pid] else { return }
                    // Build a refreshed queue from non-placeholder items
                    let real: [YouTubeVideo] = list.filter { !($0.title.isEmpty && $0.channelTitle.isEmpty) }
                    let ids = real.map { $0.id }.filter { !$0.isEmpty }
                    guard !ids.isEmpty else { return }

                    // Update queue and metadata list
                    self.queue = ids
                    self.queueVideos = real

                    // Keep currentIndex aligned to currentVideoId if possible
                    if let currentId = self.currentVideoId, let idx = ids.firstIndex(of: currentId) {
                        self.currentIndex = idx
                        // Refresh current video metadata from updated list
                        if idx < real.count { self.currentVideo = real[idx] }
                    } else {
                        // If current id is missing (e.g., cache replaced), fall back to first
                        self.currentIndex = 0
                        self.currentVideoId = ids.first
                        self.currentVideo = real.first
                    }
                }
        }
    }

    func play() {
        isPlaying = true
        controller.play()
    }

    func pause() {
        isPlaying = false
        controller.pause()
    }

    func next() {
        guard !queue.isEmpty else { return }
        // When any repeat mode is active, Next should restart the current track from the beginning.
        if repeatMode != .off {
            replayCurrentFromStart()
            return
        }
        if isShuffleEnabled {
            // Pick a random index different from current when possible
            let count = queue.count
            var idx = Int.random(in: 0..<count)
            if count > 1 {
                var attempts = 0
                while idx == currentIndex && attempts < 4 {
                    idx = Int.random(in: 0..<count)
                    attempts += 1
                }
            }
            play(at: idx)
            return
        }
        let nextIndex = currentIndex + 1
        if nextIndex < queue.count {
            currentIndex = nextIndex
            currentVideoId = queue[nextIndex]
            if nextIndex < queueVideos.count { currentVideo = queueVideos[nextIndex] }
            // Reset progress state for new track
            currentTime = 0
            duration = 0
            isPlaying = true
            controller.load(videoId: currentVideoId ?? "", autoplay: true)
        } else {
            // Reached end of queue – stop playback
            isPlaying = false
        }
    }

    func previous() {
        guard !queue.isEmpty else { return }
        let prevIndex = max(currentIndex - 1, 0)
        currentIndex = prevIndex
        currentVideoId = queue[prevIndex]
        if prevIndex < queueVideos.count { currentVideo = queueVideos[prevIndex] }
        currentTime = 0
        duration = 0
        isPlaying = true
        controller.load(videoId: currentVideoId ?? "", autoplay: true)
    }

    /// Jump to a specific index in the queue and start playing.
    func play(at index: Int) {
        guard !queue.isEmpty else { return }
        let i = min(max(index, 0), queue.count - 1)
        currentIndex = i
        currentVideoId = queue[i]
        if i < queueVideos.count { currentVideo = queueVideos[i] }
        currentTime = 0
        duration = 0
        isPlaying = true
        repeatArm = true
        controller.load(videoId: currentVideoId ?? "", autoplay: true)
    }

    // MARK: - Seeking & Duration
    func seek(to seconds: Double) {
        controller.seek(to: seconds)
        currentTime = seconds
    }

    func previewSeek(to seconds: Double) {
        // Update UI only; commit on ended of drag
        currentTime = seconds
    }

    // No periodic polling required beyond what the embed emits; controller.fetchDuration() can be called as needed.

    // MARK: - Volume
    func setVolume(_ v: Double) {
        let clamped = max(0, min(v, 1))
        volume = clamped
        controller.setVolume(percent: Int(clamped * 100))
    }

    /// Start a single-video queue (no playlist context). Useful for ad-hoc Play-in-Mini from a video panel.
    func startSingle(videoId: String, using api: YouTubeAPIService, startAtSeconds: Double? = nil, origin: LaunchOrigin = .other) {
        Task { @MainActor in
            boundAPI = api
            activePlaylistId = nil
            pendingInitialSeek = startAtSeconds
            launchOrigin = origin
            queue = [videoId]
            // Try to find full metadata for UI; otherwise create a minimal placeholder
            if let v = api.findVideo(by: videoId) {
                queueVideos = [v]
                currentVideo = v
            } else {
                let placeholder = YouTubeVideo.makePlaceholder(id: videoId)
                queueVideos = [placeholder]
                currentVideo = placeholder
            }
            currentIndex = 0
            currentVideoId = videoId
            isActive = true
            isPlaying = true
            // Ensure the bottom bar appears
            NotificationCenter.default.post(name: .showBottomPlayerBar, object: nil)
            // Kick duration fetch early for progress UI
            controller.fetchDuration { _ in }
            // Load and autoplay the video
            controller.load(videoId: videoId, autoplay: true)
            // Try to apply initial seek when ready
            applyPendingInitialSeekIfPossible()
        }
    }

    /// Stop playback completely, tear down the hidden webview, clear state and hide the mini bar.
    func stop(hideBar: Bool = true) {
        // Cancel any playlist cache observation
        playlistCacheCancellable?.cancel(); playlistCacheCancellable = nil
        // Pause and destroy controller/webview to ensure audio halts immediately
        controller.pause()
        controller.destroy()

        // Reset state so UI (sidebar Now Playing and mini bar) disappear
        isPlaying = false
        isActive = false
        currentVideoId = nil
        currentVideo = nil
        currentIndex = 0
        queue.removeAll()
        queueVideos.removeAll()
        activePlaylistId = nil
        boundAPI = nil
        currentTime = 0
        duration = 0
    pendingInitialSeek = nil
        launchOrigin = .unknown

        // Hide the bottom bar if requested
        if hideBar {
            NotificationCenter.default.post(name: .hideBottomPlayerBar, object: nil)
        }
    }
}

private extension AudioPlaylistPlayer {
    func applyPendingInitialSeekIfPossible() {
        guard let target = pendingInitialSeek, target > 0 else { return }
        // Consider the player ready when we have a positive duration or a known active state (playing/paused)
        let ps = controller.playerState
        let ready = (duration > 0) || (ps == 1 || ps == 2)
        if ready {
            controller.seek(to: target)
            currentTime = target
            // If we intend to play, ensure play resumes
            if isPlaying { controller.play() }
            pendingInitialSeek = nil
        } else {
            // Schedule a short retry; avoid tight loops
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.applyPendingInitialSeekIfPossible()
            }
        }
    }
}
