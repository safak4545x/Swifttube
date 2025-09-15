/*
 Overview / Genel Bakış
 EN: Optional bottom player bar with seek/playback controls and playlist popover; coordinates with the audio engine and video overlay.
 TR: İsteğe bağlı alt oynatıcı çubuğu; sar/oynatma kontrolleri ve playlist açılır penceresi içerir; ses motoru ve video paneliyle koordine olur.
*/

// EN: SwiftUI view for global audio controls. TR: Global ses kontrolleri için SwiftUI görünümü.
import SwiftUI

/// EN: Bottom player bar bound to AudioPlaylistPlayer; shows progress and provides controls. TR: AudioPlaylistPlayer’a bağlı alt çubuk; ilerlemeyi gösterir ve kontroller sunar.
struct BottomPlayerBar: View {
    @EnvironmentObject var youtubeAPI: YouTubeAPIService
    @ObservedObject var audio: AudioPlaylistPlayer
    // Metadata intentionally hidden in mini player per request
    @State private var isScrubbing: Bool = false
    @State private var scrubX: CGFloat = 0
    @State private var previewTime: Double = 0
    @State private var showPlaylist: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // EN: Playback progress bar with draggable seek. TR: Sürüklenebilir sarma çubuğuna sahip oynatma ilerlemesi.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                    Rectangle()
                        .fill(Color.green.opacity(0.85))
                        .frame(width: progressWidth(total: geo.size.width))
                        .animation(.linear(duration: 0.25), value: audio.currentTime)

                    // EN: Tooltip shows the target time while scrubbing. TR: Sürükleme sırasında hedef zamanı gösteren ipucu.
                    if isScrubbing && audio.duration > 0 {
                        let margin: CGFloat = 24
                        let clampedX = max(margin, min(scrubX, geo.size.width - margin))
                        VStack(spacing: 2) {
                            Text(formatTime(previewTime))
                                .font(.caption2.monospacedDigit())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .foregroundColor(.white)
                                .background(Color.black.opacity(0.85))
                                .clipShape(Capsule())
                                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                        }
                        // Position horizontally over the bar, vertically just above it
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .offset(x: clampedX, y: -22)
                        .allowsHitTesting(false)
                    }
                }
                .frame(height: 3)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard audio.duration > 0 else { return }
                            let x = max(0, min(value.location.x, geo.size.width))
                            let ratio = Double(x / geo.size.width)
                            let t = ratio * audio.duration
                            isScrubbing = true
                            scrubX = x
                            previewTime = t
                            audio.previewSeek(to: t)
                        }
                        .onEnded { value in
                            guard audio.duration > 0 else { return }
                            let x = max(0, min(value.location.x, geo.size.width))
                            let ratio = Double(x / geo.size.width)
                            let t = ratio * audio.duration
                            audio.seek(to: t)
                            isScrubbing = false
                        }
                )
                .disabled(!audio.isActive || audio.duration == 0)
            }
            .frame(height: 3)
            .background(Color.clear)
            
            Divider()
                .overlay(Color.primary.opacity(0.12))
            HStack(spacing: 12) {
                // EN: Transport controls anchored to the left. TR: Sola sabitlenmiş oynatım kontrolleri.
                HStack(spacing: 12) {
                        // Previous (subtle circle)
                        Button(action: { audio.previous() }) {
                            ZStack {
                                Circle()
                                    .fill(Color.secondary.opacity(0.18))
                                Image(systemName: "backward.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.primary)
                            }
                            .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .help("Previous")
                        .disabled(!audio.isActive)

                        // Play/Pause (green circle)
                        Button(action: { audio.isPlaying ? audio.pause() : audio.play() }) {
                            ZStack {
                                Circle()
                                    .fill(Color.green)
                                Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .frame(width: 34, height: 34)
                        }
                        .buttonStyle(.plain)
                        .help(audio.isPlaying ? "Pause" : "Play")
                        .disabled(!audio.isActive)

                        // Next (subtle circle)
                        Button(action: { audio.next() }) {
                            ZStack {
                                Circle()
                                    .fill(Color.secondary.opacity(0.18))
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.primary)
                            }
                            .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .help("Next")
                        .disabled(!audio.isActive)

                        // EN: Shuffle toggle (right of Next). TR: Karıştırma anahtarı (İleri’nin sağında).
                        Button(action: { audio.setShuffle(!audio.isShuffleEnabled) }) {
                            ZStack {
                                Circle()
                                    .fill(audio.isShuffleEnabled ? Color.green : Color.secondary.opacity(0.18))
                                Image(systemName: "shuffle")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(audio.isShuffleEnabled ? .white : .primary)
                            }
                            .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .help(audio.isShuffleEnabled ? "Shuffle on" : "Shuffle off")
                        .disabled(!audio.isActive)

                        // EN: Repeat cycles Off → Once → Infinite. TR: Tekrar sırası Kapalı → Bir Kez → Sonsuz.
                        Button(action: { audio.cycleRepeatMode() }) {
                            ZStack {
                                Circle()
                                    .fill(audio.repeatMode == .off ? Color.secondary.opacity(0.18) : Color.green)
                                Image(systemName: "repeat")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(audio.repeatMode == .off ? Color.primary : Color.white)
                            }
                            .frame(width: 28, height: 28)
                            .overlay(alignment: .topTrailing) {
                                // EN: Badge shows 1 (once) or ∞ (infinite). TR: Rozet 1 (bir kez) veya ∞ (sonsuz) gösterir.
                                if audio.repeatMode != .off {
                                    Text(audio.repeatMode == .once ? "1" : "∞")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.black.opacity(0.7))
                                        .clipShape(Capsule())
                                        .offset(x: 3, y: -3)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .help({
                            switch audio.repeatMode {
                            case .off: return "Repeat off"
                            case .once: return "Repeat once"
                            case .infinite: return "Repeat infinite"
                            }
                        }())
                        .disabled(!audio.isActive)
                }
                // EN: Volume slider next to transport controls. TR: Oynatım kontrollerinin yanında ses kaydırıcısı.
                HStack(spacing: 8) {
                    Image(systemName: audio.volume <= 0.01 ? "speaker.slash.fill" : (audio.volume < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.3.fill"))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Slider(value: Binding(
                        get: { audio.volume },
                        set: { v in audio.setVolume(v) }
                    ), in: 0...1)
                    .frame(width: 140)
                    .tint(.green)
                }
                .opacity(audio.isActive ? 1 : 0.5)

                Spacer(minLength: 8)

                // EN: Playlist popover (right side). TR: Playlist açılır penceresi (sağ).
                Button(action: { showPlaylist.toggle() }) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(8)
                        .background(Circle().fill(Color.secondary.opacity(0.18)))
                }
                .buttonStyle(.plain)
                .help("Playlist")
                .disabled(!audio.isActive || audio.queueVideos.isEmpty)
                .popover(isPresented: $showPlaylist, arrowEdge: .top) {
                    // If launched from video panel and no active playlist context, show user's playlists to start from
                    if (audio.launchOrigin == .videoPanel) && ((audio.activePlaylistId ?? "").isEmpty) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Playlists")
                                .font(.headline)
                            if (youtubeAPI.userPlaylists.isEmpty) {
                                Text("No playlists yet")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(youtubeAPI.userPlaylists) { p in
                                            Button(action: {
                                                showPlaylist = false
                                                Task { @MainActor in
                                                    if youtubeAPI.cachedPlaylistVideos[p.id]?.isEmpty ?? true {
                                                        await youtubeAPI.ensurePlaylistLoadedCount(playlist: p, minCount: 1)
                                                    }
                                                    audio.start(playlistId: p.id, startIndex: 0, using: youtubeAPI, startAtSeconds: nil, origin: .other)
                                                    audio.play()
                                                }
                                            }) {
                                                HStack {
                                                    // Prefer custom cover file path, else remote thumbnail URL; fallback to bundled asset by coverName
                                                    if let imgURL = resolvePlaylistCoverURL(p) {
                                                        CachedAsyncImage(url: imgURL) { img in
                                                            img.resizable().scaledToFill()
                                                        } placeholder: { Color.gray.opacity(0.2) }
                                                        .frame(width: 52, height: 32)
                                                        .clipped().cornerRadius(4)
                                                    } else {
                                                        Image(p.coverName ?? "playlist")
                                                            .resizable()
                                                            .scaledToFill()
                                                            .frame(width: 52, height: 32)
                                                            .clipped()
                                                            .cornerRadius(4)
                                                    }
                                                    Text(p.title).lineLimit(1)
                                                    Spacer()
                                                    Image(systemName: "play.fill")
                                                        .foregroundStyle(.secondary)
                                                }
                                                .padding(6)
                                                .background(Color.secondary.opacity(0.08))
                                                .cornerRadius(6)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                        .frame(width: 320, height: 260)
                        .padding(10)
                    } else {
                        // EN: Use API bound to the audio engine; fallback to environment. TR: Sese bağlı API’yi kullan; yoksa ortamı kullan.
                        PlaylistPopover(api: audio.boundAPI ?? youtubeAPI, audio: audio)
                            .frame(width: 360, height: 380)
                            .padding(8)
                    }
                }

                // EN: Open video overlay at current timestamp (exits mini). TR: Geçerli zamanda video panelini aç (mini’den çıkar).
                Button(action: {
                    guard let vid = audio.currentVideoId else { return }
                    let time = audio.currentTime
                    // Hide mini first (stop audio but don't tear down UI state elsewhere)
                    audio.stop()
                    // Ask root to open overlay panel for this video at current time
                    var info: [String: Any] = ["videoId": vid]
                    if time > 0 { info["time"] = time }
                    if let pid = audio.activePlaylistId, !pid.isEmpty { info["playlistId"] = pid }
                    NotificationCenter.default.post(name: .openVideoOverlay, object: nil, userInfo: info)
                }) {
                    Image(systemName: "play.rectangle")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(8)
                        .background(Circle().fill(Color.secondary.opacity(0.18)))
                }
                .buttonStyle(.plain)
                .help("Videoya geç")
                .disabled(!audio.isActive || audio.currentVideoId == nil)

                // EN: Close the mini bar and stop playback. TR: Mini çubuğu kapat ve oynatmayı durdur.
                Button(action: {
                    // Fully stop playback and hide the bar
                    audio.stop()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(8)
                        .background(Circle().fill(Color.secondary.opacity(0.18)))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .help("Kapat")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    // Match the app's upper toolbar appearance
                    VisualEffectView(material: .titlebar, blendingMode: .withinWindow)
                    // Subtle top divider line for separation from content
                    Rectangle()
                        .fill(Color(NSColor.separatorColor).opacity(0.18))
                        .frame(height: 0.5)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .allowsHitTesting(false)
                }
            )
        }
    }

    private func progressWidth(total: CGFloat) -> CGFloat {
        guard audio.duration > 0 else { return 0 }
        let ratio = max(0, min(audio.currentTime / audio.duration, 1))
        return total * CGFloat(ratio)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let s = Int(seconds.rounded())
        if s < 3600 { return String(format: "%d:%02d", s/60, s%60) }
        return String(format: "%d:%02d:%02d", s/3600, (s%3600)/60, s%60)
    }

    // EN: Resolve cover image URL (prefer local custom, else remote). TR: Kapak görseli URL’sini çöz (önce yerel özel, yoksa uzak).
    private func resolvePlaylistCoverURL(_ p: YouTubePlaylist) -> URL? {
        if let path = p.customCoverPath, !path.isEmpty, FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        if !p.thumbnailURL.isEmpty, let u = URL(string: p.thumbnailURL) {
            return u
        }
        return nil
    }
}

// MARK: - Playlist Popover
private struct PlaylistPopover: View {
    let api: YouTubeAPIService
    @ObservedObject var audio: AudioPlaylistPlayer
    @State private var isLoadingMore: Bool = false

    // EN: Resolve active playlist title from API (user or searched). TR: Etkin playlist başlığını API’den çöz (kullanıcı veya arama).
    private var activePlaylistTitle: String? {
        guard let pid = audio.activePlaylistId, !pid.isEmpty else { return nil }
        if let p = api.userPlaylists.first(where: { $0.id == pid }) {
            return p.title
        }
        if let p = api.searchedPlaylists.first(where: { $0.id == pid }) {
            return p.title
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Playlist")
                    .font(.headline)
                Spacer()
                // Prefer showing the playlist name in the header; fallback to current track
                if let title = activePlaylistTitle, !title.isEmpty {
                    Text(title)
                        .font(.subheadline)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                } else if let current = audio.currentVideo {
                    Text(current.title)
                        .font(.subheadline)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 4)

            if audio.queueVideos.isEmpty {
                ContentUnavailableView(
                    "No items",
                    systemImage: "list.bullet",
                    description: Text("Start a playlist to see items here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        // Use stable identity by video id to prevent row reuse causing image glitches
                        ForEach(Array(audio.queueVideos.enumerated()), id: \.element.id) { pair in
                            let idx = pair.offset
                            let vid = pair.element
                            PlaylistRow(index: idx, video: vid, isCurrent: vid.id == audio.currentVideoId) {
                                audio.play(at: idx)
                            }
                            .onAppear {
                                triggerLoadMoreIfNeeded(currentIndex: idx)
                            }
                        }
                        footer
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var footer: some View {
        let pid = audio.activePlaylistId ?? ""
        let realLoaded: Int = (api.cachedPlaylistVideos[pid] ?? []).filter { !($0.title.isEmpty && $0.channelTitle.isEmpty) }.count
        let total: Int? = api.totalPlaylistCountById[pid]
        return Group {
            if let total, realLoaded >= total, total > 0 {
                Text("Tümü yüklendi")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 6)
            } else if isLoadingMore {
                ProgressView().padding(.vertical, 6)
            }
        }
    }

    private func triggerLoadMoreIfNeeded(currentIndex: Int) {
        guard let pid = audio.activePlaylistId else { return }
    // EN: Trigger incremental load when near the end. TR: Sona yaklaşınca artımlı yüklemeyi tetikle.
        let cached = api.cachedPlaylistVideos[pid] ?? []
        let real = cached.filter { !($0.title.isEmpty && $0.channelTitle.isEmpty) }
        let realCount = real.count
        // If we're within last 4 items, ask for 40 more (same policy as PlaylistView)
        let isNearEnd = currentIndex >= max(0, realCount - 4)
        if isLoadingMore || !isNearEnd { return }
        if let total = api.totalPlaylistCountById[pid], realCount >= total { return }

        isLoadingMore = true
        let target = realCount + 40
        Task { @MainActor in
            // Prefer id-based loader to support playlists not present in userPlaylists
            await api.ensurePlaylistLoadedCount(playlistId: pid, minCount: target)
            isLoadingMore = false
        }
    }
}

private struct PlaylistRow: View {
    let index: Int
    let video: YouTubeVideo
    let isCurrent: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Text(String(index + 1))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 18, alignment: .trailing)
                // EN: Thumbnail (cached, keyed by id). TR: Küçük görsel (önbellekli, id’ye göre anahtarlanmış).
                CachedAsyncImage(url: URL(string: youtubeThumbnailURL(video.id, quality: .mqdefault))) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Color.gray.opacity(0.2)
                }
                .frame(width: 52, height: 32)
                .clipped()
                .cornerRadius(4)
                .id(video.id)

                VStack(alignment: .leading, spacing: 2) {
                    Text(video.title.isEmpty ? "(untitled)" : video.title)
                        .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                        .lineLimit(1)
                    Text(video.channelTitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if isCurrent {
                    Image(systemName: "speaker.wave.2.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .padding(6)
            .background(isCurrent ? Color.green.opacity(0.12) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .help(video.title)
    }
}

//#Preview {
//    VStack(spacing: 0) {
//        Spacer()
//        BottomPlayerBar(audio: AudioPlaylistPlayer())
//    }
//}
