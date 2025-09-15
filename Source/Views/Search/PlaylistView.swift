/*
 Overview / Genel Bakış
 EN: Detailed playlist view with counts, items, and play/add actions.
 TR: Sayımlar, öğeler ve oynat/ekle eylemleri içeren playlist detayı.
*/

import SwiftUI
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

struct PlaylistView: View {
    @EnvironmentObject var i18n: Localizer
    @ObservedObject var youtubeAPI: YouTubeAPIService
    let playlist: YouTubePlaylist
    // Search result görünümünde artı butonu göstermek için bayrak
    var isSearchResult: Bool = false
    // Show green Play button in header (explicit). On embedded playlist mode, pass false.
    var showPlayButton: Bool = true
    // Tek açık kalsın: dışarıdan gelen selectedOpenPlaylistId ile kontrol edilir
    @Binding var openPlaylistId: String?
    // Dış ScrollView'i (sayfa) hover esnasında devre dışı bırakmak için
    @Binding var disableOuterScroll: Bool
    // Optional click handlers to override default NotificationCenter behavior
    // When provided, these are called instead of posting notifications (used in Tab mode)
    var onRowLeftClick: ((String, Int) -> Void)? = nil
    var onRowMiddleClick: ((String, Int) -> Void)? = nil
    var onPlayLeftClick: (() -> Void)? = nil
    var onPlayMiddleClick: (() -> Void)? = nil

    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var loadedCount: Int = 0
    @State private var showRenamePopover = false
    @State private var draftTitle: String = ""
    @FocusState private var titleFieldFocused: Bool
    // Selection state for playlist-mode highlight
    @State private var selectedVideoId: String? = nil
    // Play butonu animasyonu için lokal state
    @State private var playPressed: Bool = false
    @State private var rippleActive: Bool = false
    @State private var rippleStart: Bool = false
    // Mini player butonu animasyonu için lokal state
    @State private var miniPressed: Bool = false
    @State private var miniRippleActive: Bool = false
    @State private var miniRippleStart: Bool = false

    var isOpen: Bool { openPlaylistId == playlist.id }
    // Already added to user's playlists?
    var isAlreadyAdded: Bool {
        youtubeAPI.userPlaylists.contains { $0.id == playlist.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if isOpen {
                // Keep the separator static, animate only the content so it appears from below the line
                Rectangle()
                    .fill(Color.gray.opacity(0.35))
                    .frame(height: 1)
                    .padding(.horizontal, 8)

                content
                    .padding(.top, 6)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.98, anchor: .top).combined(with: .opacity),
                            removal: .opacity
                        )
                    )
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(isOpen ? 0.18 : 0.12), lineWidth: 1)
        )
        .cornerRadius(10)
    }

    private var header: some View {
        Button(action: toggleOpen) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.15))
                    #if os(macOS)
                    // Avoid remote image fetches; use local/custom cover if available, else a placeholder symbol.
                    if let nsImg = resolvePlaylistCoverImage() {
                        Image(nsImage: nsImg)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 60)
                            .clipped()
                    } else {
                        Image(systemName: "rectangle.on.rectangle")
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(.secondary)
                            .padding(10)
                    }
                    #else
                    // iOS path (if ever built): try SwiftUI Image by name, else fallback
                    Image(playlist.coverName ?? "playlist")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 60)
                        .clipped()
                    #endif
                }
                .frame(width: 80, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
                #if os(macOS)
                .contextMenu {
                    // Varsayılan kapak fotoğrafları
                    Menu(i18n.t(.playlistMenuDefaultCovers)) {
                        Button("playlist") { setDefaultCover("playlist") }
                        Button("playlist2") { setDefaultCover("playlist2") }
                        Button("playlist3") { setDefaultCover("playlist3") }
                        Button("playlist4") { setDefaultCover("playlist4") }
                    }
                    // Dosyadan yükle
                    Button(i18n.t(.playlistMenuUploadFromFile)) { pickCustomCoverFromDisk() }
                    Divider()
                    Button(i18n.t(.playlistMenuResetToDefaults)) { resetCover() }
                }
                #endif

                VStack(alignment: .leading, spacing: 4) {
                    Text(playlist.title.isEmpty ? "Playlist" : playlist.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        #if os(macOS)
                        .contextMenu {
                            Button(i18n.t(.playlistContextRename)) {
                                draftTitle = playlist.title
                                showRenamePopover = true
                            }
                        }
                        .popover(isPresented: $showRenamePopover, arrowEdge: .top) {
                            HStack(spacing: 8) {
                                Menu {
                                    let choices = ["🔥","⭐️","🎯","🎵","🎮","⚽️","📈","🎬","📰","🧪","🧠","📚","🍿","🚀","💡"]
                                    ForEach(choices, id: \.self) { e in
                                        Button(e) {
                                            if !draftTitle.hasPrefix(e + " ") { draftTitle = e + " " + draftTitle }
                                        }
                                    }
                                } label: {
                                    Text("😀")
                                        .font(.system(size: 14))
                                        .frame(width: 28, height: 24)
                                        .background(Color.secondary.opacity(0.12))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .menuStyle(.borderlessButton)
                                .menuIndicator(.hidden)
                                .fixedSize()
                                TextField(i18n.t(.playlistNamePlaceholder), text: $draftTitle, onCommit: commitRename)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 220)
                                    .focused($titleFieldFocused)
                                Button(i18n.t(.cancel)) { showRenamePopover = false }
                                    .keyboardShortcut(.cancelAction)
                                Button(i18n.t(.ok)) { commitRename() }
                                    .keyboardShortcut(.defaultAction)
                                    .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                            .padding(10)
                            .onAppear { titleFieldFocused = true }
                            .onExitCommand { showRenamePopover = false }
                        }
                        #endif
                    HStack(spacing: 6) {
                        if let total = youtubeAPI.totalPlaylistCountById[playlist.id], total > 0 {
                            Text("\(total) \(i18n.t(.videoCountSuffix))")
                        } else if youtubeAPI.fetchingPlaylistCountIds.contains(playlist.id) || youtubeAPI.totalPlaylistCountById[playlist.id] == nil {
                            // Show skeleton while authoritative count is being fetched
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.25))
                                .frame(width: 60, height: 10)
                                .shimmering()
                                .accessibilityHidden(true)
                        } else if playlist.videoCount > 0 {
                            Text("\(playlist.videoCount) \(i18n.t(.videoCountSuffix))")
                        } else if let cached = youtubeAPI.cachedPlaylistVideos[playlist.id]?.count, cached > 0 {
                            Text("\(cached) \(i18n.t(.videoCountSuffix))")
                        }
                    }
                    // Request authoritative count via official API (batched)
                    .task { youtubeAPI.queuePlaylistCountFetch([playlist.id]) }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
                Spacer()
                // EN: Green circular Play button (overlay/tab). TR: Yeşil dairesel Oynat düğmesi (overlay/sekme).
                if showPlayButton {
                    ZStack {
                        Image(systemName: "play.fill")
                            .foregroundColor(.white)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Color.green))
                            // Küçük bir bounce efekti (şekli/konumu değiştirmeden ölçek animasyonu)
                            .scaleEffect(playPressed ? 0.9 : 1.0)
                            .animation(.spring(response: 0.22, dampingFraction: 0.58), value: playPressed)
                            // Basınca dışa yayılan halka efekti (yalnızca basıldığında görünür)
                            .overlay(
                                Group {
                                    if rippleActive {
                                        Circle()
                                            .stroke(Color.green.opacity(0.55), lineWidth: 3)
                                            .scaleEffect(rippleStart ? 1.8 : 0.6)
                                            .opacity(rippleStart ? 0 : 0.55)
                                            .animation(.easeOut(duration: 0.5), value: rippleStart)
                                    }
                                }
                            )
                        #if os(macOS)
                        // Capture left vs middle click: left opens overlay panel, middle opens in a new tab
                        MouseClickCatcher(
                            onLeft: {
                                triggerPlayButtonAnimation()
                                if let onPlayLeftClick { onPlayLeftClick() }
                                else { NotificationCenter.default.post(name: .openPlaylistModeOverlay, object: nil, userInfo: ["playlistId": playlist.id]) }
                            },
                            onMiddle: {
                                triggerPlayButtonAnimation()
                                if let onPlayMiddleClick { onPlayMiddleClick() }
                                else { NotificationCenter.default.post(name: .openPlaylistMode, object: nil, userInfo: ["playlistId": playlist.id]) }
                            }
                        )
                        .frame(width: 26, height: 26)
                        .allowsHitTesting(true)
                        #endif
                    }
                    .contentShape(Circle())
                    #if !os(macOS)
                    .onTapGesture {
                        triggerPlayButtonAnimation()
                        if let onPlayLeftClick { onPlayLeftClick() }
                        else { NotificationCenter.default.post(name: .openPlaylistModeOverlay, object: nil, userInfo: ["playlistId": playlist.id]) }
                    }
                    #endif
                    .help(i18n.t(.play))

                    // EN: Mini player button (audio playlist start). TR: Mini oynatıcı düğmesi (ses playlisti başlatır).
                    ZStack {
                        Image(systemName: "play.square.stack")
                            .foregroundColor(.white)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Color.green))
                            // Bounce animation
                            .scaleEffect(miniPressed ? 0.9 : 1.0)
                            .animation(.spring(response: 0.22, dampingFraction: 0.58), value: miniPressed)
                            // Ripple animation
                            .overlay(
                                Group {
                                    if miniRippleActive {
                                        Circle()
                                            .stroke(Color.green.opacity(0.55), lineWidth: 3)
                                            .scaleEffect(miniRippleStart ? 1.8 : 0.6)
                                            .opacity(miniRippleStart ? 0 : 0.55)
                                            .animation(.easeOut(duration: 0.5), value: miniRippleStart)
                                    }
                                }
                            )
                        #if os(macOS)
                        MouseClickCatcher(
                            onLeft: {
                                triggerMiniButtonAnimation()
                                NotificationCenter.default.post(name: .startAudioPlaylist, object: nil, userInfo: ["playlistId": playlist.id])
                            },
                            onMiddle: {
                                triggerMiniButtonAnimation()
                                NotificationCenter.default.post(name: .startAudioPlaylist, object: nil, userInfo: ["playlistId": playlist.id])
                            }
                        )
                        .frame(width: 26, height: 26)
                        .allowsHitTesting(true)
                        #endif
                    }
                    .contentShape(Circle())
                    #if !os(macOS)
                    .onTapGesture {
                        triggerMiniButtonAnimation()
                        NotificationCenter.default.post(name: .startAudioPlaylist, object: nil, userInfo: ["playlistId": playlist.id])
                    }
                    #endif
                    .help("Mini Player")
                }
                // EN: In search results: show add/remove to user library. TR: Arama sonuçlarında: kütüphaneye ekle/kaldır.
                if isSearchResult {
                        if isAlreadyAdded {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .imageScale(.large)
                                    .transition(.scale.combined(with: .opacity))
                                Button(action: {
                                    Task { @MainActor in
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                            youtubeAPI.removeUserPlaylist(playlistId: playlist.id)
                                        }
                                    }
                                }) {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red)
                                        .imageScale(.large)
                                        .help(i18n.t(.delete))
                                }
                                .buttonStyle(.plain)
                            }
                        } else {
                        Button(action: {
                            Task { @MainActor in
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                    youtubeAPI.addSearchedPlaylistToUser(playlist)
                                }
                            }
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.green)
                                .imageScale(.large)
                                .help(i18n.t(.add))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding(12)
        }
        .buttonStyle(.plain)
    }

    private func triggerPlayButtonAnimation() {
        // Bounce
        playPressed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { playPressed = false }
        // Ripple
        rippleActive = true
        rippleStart = false
        // Sonraki runloop'ta animasyonu başlat
        DispatchQueue.main.async {
            rippleStart = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.52) {
                rippleActive = false
                rippleStart = false
            }
        }
    }

    private func triggerMiniButtonAnimation() {
        // Bounce
        miniPressed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { miniPressed = false }
        // Ripple
        miniRippleActive = true
        miniRippleStart = false
        DispatchQueue.main.async {
            miniRippleStart = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.52) {
                miniRippleActive = false
                miniRippleStart = false
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isLoading {
                ProgressView(i18n.t(.loading))
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if let videos = youtubeAPI.cachedPlaylistVideos[playlist.id], !videos.isEmpty {
                // If cache is filled with placeholder items (empty title+channel), keep showing a loader
                if videos.allSatisfy({ $0.title.isEmpty && $0.channelTitle.isEmpty }) {
                    ProgressView(i18n.t(.loading))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .task { loadIfNeeded() }
                } else {
        ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(spacing: 10) {
                            // EN: Numbered compact rows without thumbnails. TR: Küçük resimsiz numaralı kompakt satırlar.
        ForEach(Array(videos.enumerated()), id: \.offset) { idx, v in
                                // Skip placeholder rows that only carry count
                                if !(v.title.isEmpty && v.channelTitle.isEmpty) {
                                    HStack(alignment: .top, spacing: 8) {
                                        // 1, 2, 3 ... prefix
                                        Text("\(idx + 1)-")
                                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .frame(width: 18, alignment: .trailing)

                                        VStack(alignment: .leading, spacing: 3) {
                                            // First line: duration + title
                                            (Text(v.durationText.isEmpty ? "" : v.durationText + " ")
                                                .foregroundColor(.secondary)
                                             + Text(v.title))
                                            .font(.subheadline)
                                            .foregroundColor(.primary)
                                            .lineLimit(2)

                                            // Channel name under the title
                                            Text(v.channelTitle)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill((selectedVideoId == v.id) ? Color.accentColor.opacity(0.12) : Color.clear)
                                            .animation(.easeInOut(duration: 0.18), value: selectedVideoId)
                                    )
                                    // Tag each real row with a stable id for programmatic scroll
                                    .id(v.id)
                                    #if os(macOS)
                                    // Satır tıklaması: sol tık overlay video panelinde, orta tık sekmede
                                    .overlay(
                                        MouseClickCatcher(
                                            onLeft: {
                                                if let onRowLeftClick { onRowLeftClick(v.id, idx) }
                                                else { NotificationCenter.default.post(name: .openPlaylistModeOverlay, object: nil, userInfo: ["playlistId": playlist.id, "videoId": v.id, "index": idx]) }
                                            },
                                            onMiddle: {
                                                if let onRowMiddleClick { onRowMiddleClick(v.id, idx) }
                                                else { NotificationCenter.default.post(name: .openPlaylistMode, object: nil, userInfo: ["playlistId": playlist.id, "videoId": v.id, "index": idx]) }
                                            }
                                        )
                                        .allowsHitTesting(true)
                                    )
                                    #else
                                    .onTapGesture { if let onRowLeftClick { onRowLeftClick(v.id, idx) } else { NotificationCenter.default.post(name: .openPlaylistModeOverlay, object: nil, userInfo: ["playlistId": playlist.id, "videoId": v.id, "index": idx]) } }
                                    #endif
                                    .contentShape(Rectangle())
                                    // EN: Infinite scroll trigger when last real item appears. TR: Son gerçek öğe göründüğünde sonsuz kaydırma tetikleyicisi.
                                    .onAppear {
                                        let realCount = videos.filter { !($0.title.isEmpty && $0.channelTitle.isEmpty) }.count
                                        if idx >= realCount - 1 {
                                            triggerLoadMore(currentRealCount: realCount)
                                        }
                                    }
                                }
                            }
                            // Footer: show either loading spinner or "Tümü yüklendi" when complete
                            let realLoaded = videos.filter { !($0.title.isEmpty && $0.channelTitle.isEmpty) }.count
                            if let total = youtubeAPI.totalPlaylistCountById[playlist.id], realLoaded >= total {
                                Text("Tümü yüklendi")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 8)
                            } else if isLoadingMore {
                                ProgressView()
                                    .padding(.vertical, 8)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    .frame(maxHeight: 360) // kendi içinde scroll
#if os(macOS)
                    // Hover alt panel üzerindeyken dıştaki ScrollView'i devre dışı bırak
                    .onHover { hovering in
                        if isOpen {
                            disableOuterScroll = hovering
                        }
                    }
#endif
                    // Scroll to selected row whenever selection changes
                    .onChange(of: selectedVideoId) { id in
                        guard let id = id else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                    // Retry scroll after content grows (e.g., after loading more)
                    .onChange(of: youtubeAPI.cachedPlaylistVideos[playlist.id]?.count ?? 0) { _ in
                        guard let id = selectedVideoId else { return }
                        // Use a short async to wait layout
                        DispatchQueue.main.async {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                    // Receive selection sync + scroll to it
                    .onReceive(NotificationCenter.default.publisher(for: .openPlaylistVideo)) { note in
                        if let pid = note.userInfo?["playlistId"] as? String, pid == playlist.id,
                           let vid = note.userInfo?["videoId"] as? String {
                            selectedVideoId = vid
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo(vid, anchor: .center)
                            }
                        }
                    }
                }
                }
            } else {
                Text(i18n.t(.videosWillAppearHere))
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
        // Açılan alt panel, playlist kartıyla aynı renkte ve nötr kenarlıkla
    .padding(.horizontal, 8)
    .padding(.top, 6)
        .onAppear { loadIfNeeded() }
        .onDisappear { disableOuterScroll = false }
    }

    private func toggleOpen() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86, blendDuration: 0.2)) {
            if isOpen {
                openPlaylistId = nil
                disableOuterScroll = false
            } else {
                openPlaylistId = playlist.id
            }
        }
    }

    // Basit süre görünürlük kontrolü: süre varsa ve kısa (<= 65 sn) değilse
    private func shouldShowDuration(_ v: YouTubeVideo) -> Bool {
        guard !v.durationText.isEmpty else { return false }
        if let secs = v.durationSeconds, secs <= 65 { return false }
        return true
    }

    private func loadIfNeeded() {
        let cached = youtubeAPI.cachedPlaylistVideos[playlist.id] ?? []
        // Count only real items (placeholders have empty title+channel)
        let realCount = cached.filter { !($0.title.isEmpty && $0.channelTitle.isEmpty) }.count
        // If fewer than 40 real items are available, request at least 40 (bigger first burst)
        let initialTarget = 40
        guard realCount < initialTarget else { return }
        isLoading = realCount == 0
        Task { @MainActor in
            // Ensure we have at least `initialTarget` items (service replaces placeholder-only arrays)
            await youtubeAPI.ensurePlaylistLoadedCount(playlist: playlist, minCount: initialTarget)
            isLoading = false
        }
    }

    private func triggerLoadMore(currentRealCount: Int) {
        // Debounce duplicate triggers
        if isLoadingMore { return }
    // Stop when we know total and already loaded all
    if let total = youtubeAPI.totalPlaylistCountById[playlist.id], currentRealCount >= total { return }
        // If we know total count via placeholder cache, stop when reached
        if let cached = youtubeAPI.cachedPlaylistVideos[playlist.id], !cached.isEmpty,
           cached.allSatisfy({ !$0.title.isEmpty || !$0.channelTitle.isEmpty }) {
            // No placeholder-only array, but we can still guard by not requesting if growth did not happen
        }
        isLoadingMore = true
    let target = currentRealCount + 40
        Task { @MainActor in
            await youtubeAPI.ensurePlaylistLoadedCount(playlist: playlist, minCount: target)
            isLoadingMore = false
        }
    }
}

// MARK: - Helpers (macOS)
#if os(macOS)
private extension PlaylistView {
    // Transparent NSView overlay to capture left vs middle mouse clicks
    struct MouseClickCatcher: NSViewRepresentable {
        var onLeft: () -> Void
        var onMiddle: () -> Void

        func makeNSView(context: Context) -> NSView {
            return ClickCatcherView(onLeft: onLeft, onMiddle: onMiddle)
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            if let v = nsView as? ClickCatcherView {
                v.onLeft = onLeft
                v.onMiddle = onMiddle
            }
        }

        final class ClickCatcherView: NSView {
            var onLeft: () -> Void
            var onMiddle: () -> Void
            init(onLeft: @escaping () -> Void, onMiddle: @escaping () -> Void) {
                self.onLeft = onLeft
                self.onMiddle = onMiddle
                super.init(frame: .zero)
                wantsLayer = true
                layer?.backgroundColor = .clear
            }
            required init?(coder: NSCoder) { nil }
            override func hitTest(_ point: NSPoint) -> NSView? { return self }
            override func mouseDown(with event: NSEvent) { onLeft() }
            override func otherMouseDown(with event: NSEvent) {
                if event.buttonNumber == 2 { onMiddle() } else { onLeft() }
            }
        }
    }

    func resolvePlaylistCoverImage() -> NSImage? {
        // Öncelik: özel dosya yolu
        if let path = playlist.customCoverPath, !path.isEmpty, let img = NSImage(contentsOfFile: path) {
            return img
        }
        // Normalize historical misspellings to valid asset names
        let rawBase = playlist.coverName ?? "playlist"
        let base: String = {
            switch rawBase {
            case "playist": return "playlist" // historical typo
            case "playlist3": return "playlist3" // historical typo
            default: return rawBase
            }
        }()
        var candidates: [String] = [base]
        // Backward-compatibility: try alias if a historical typo was saved in older data
        if rawBase == "playist" { candidates.append("playlist") }
        if rawBase == "playlist3" { candidates.append("playlist3") }
        // 1) Asset catalog
        for name in candidates { if let img = NSImage(named: name) { return img } }
        // 2) Examples subdirectory
        for name in candidates {
            if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Examples"), let img = NSImage(contentsOf: url) { return img }
        }
        // 3) Root fallback
        if let url = Bundle.main.url(forResource: "playlist", withExtension: "png"), let img = NSImage(contentsOf: url) { return img }
        return nil
    }

    func commitRename() {
        let title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        Task { @MainActor in
            youtubeAPI.renamePlaylist(playlistId: playlist.id, to: title)
            showRenamePopover = false
        }
    }

    func setDefaultCover(_ name: String) {
        Task { @MainActor in
            youtubeAPI.setPlaylistCoverName(playlistId: playlist.id, name: name)
        }
    }

    func resetCover() {
        Task { @MainActor in
            youtubeAPI.resetPlaylistCover(playlistId: playlist.id)
        }
    }

    func pickCustomCoverFromDisk() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if #available(macOS 12.0, *) {
            panel.allowedContentTypes = [.png, .jpeg]
        } else {
            panel.allowedFileTypes = ["png", "jpg", "jpeg"]
        }
    panel.prompt = i18n.t(.choose)
    panel.begin { response in
            if response == .OK, let url = panel.url {
                Task { @MainActor in
                    youtubeAPI.setPlaylistCustomCoverPath(playlistId: playlist.id, path: url.path)
                }
            }
        }
    }
}
#endif
