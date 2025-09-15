/*
 File Overview (EN)
 Purpose: Left-side content stack for video pages: player, title, channel row, actions, and description/metadata.
 Key Responsibilities:
 - Compose player with surrounding UI and bind to app-wide playback state
 - Render title/channel row and action buttons with localization
 - Manage description expansion and related layout
 Used By: Video detail page main column.

 Dosya Özeti (TR)
 Amacı: Video sayfaları için sol taraftaki içerik yığını: oynatıcı, başlık, kanal satırı, eylemler ve açıklama/metadata.
 Ana Sorumluluklar:
 - Oynatıcıyı çevresindeki arayüzle birleştirmek ve uygulama çapı oynatma durumuna bağlamak
 - Başlık/kanal satırı ve eylem düğmelerini yerelleştirme ile sunmak
 - Açıklama genişletmeyi ve ilgili yerleşimi yönetmek
 Nerede Kullanılır: Video detay sayfasının ana sütunu.
*/

import SwiftUI

struct LeftVideoContentView: View {
    @EnvironmentObject var i18n: Localizer
    @EnvironmentObject private var audio: AudioPlaylistPlayer
    let video: YouTubeVideo
    @ObservedObject var api: YouTubeAPIService
    // Kanal açma callback'i (Video panelinden kanala geçiş)
    var onOpenChannel: ((YouTubeChannel) -> Void)? = nil
    // Paneli kapatma callback'i (Mini Player'a geçerken panel kapansın)
    var onClosePanel: (() -> Void)? = nil
    // Inline player'ın o anki zamanını okuma (VideoDetailView sağlar)
    var getCurrentTime: (() -> Double)? = nil
    // Eğer panel playlist modunda açıldıysa bağlamı (mini player'ı playlistte başlatmak için)
    var playlistContext: PlaylistContext? = nil
    
    @State private var likeCount: String = "0"
    @State private var showShareMenu = false
    @State private var showCommentSortMenu = false
    @State private var commentSortOption: CommentSortOption = .relevance
    @State private var expandedComments: Set<String> = []
    @State private var expandedReplies: Set<String> = []
    @State private var isDescriptionExpanded = false
    @State private var fullDescription: String? = nil
    @State private var isFetchingFullDescription = false
    // Yorumlar varsayılan olarak gizli gelsin
    @State private var showComments: Bool = false
    // Playlist popover state
    @State private var showPlaylistPopover = false
    @State private var newPlaylistName: String = ""
    @FocusState private var newPlaylistNameFocused: Bool
    @State private var tempCoverName: String? = nil
    // Toast state
    @State private var showAddedToast: Bool = false
    // Panelde görüntülenecek izlenme ve tarih için fallback (playlist cache henüz zenginleşmemişse)
    @State private var displayViewCountFallback: String = ""
    @State private var displayPublishedAtFallback: String = ""
    // Başlık ve kanal adı/ID için de fallback (placeholder veya boşsa)
    @State private var displayTitleFallback: String = ""
    @State private var displayChannelTitleFallback: String = ""
    @State private var displayChannelIdFallback: String = ""
    
    enum CommentSortOption: String, CaseIterable {
        case mostLiked
        case newest
        case relevance
        
        var systemImage: String {
            switch self {
            case .mostLiked: return "hand.thumbsup.fill"
            case .newest: return "clock.fill"
            case .relevance: return "star.fill"
            }
        }
        
        var apiParameter: String {
            switch self {
            case .mostLiked: return "relevance"
            case .newest: return "time"
            case .relevance: return "relevance"
            }
        }

    @MainActor
    func title(_ i18n: Localizer) -> String {
            switch self {
            case .mostLiked: return i18n.t(.sortMostLiked)
            case .newest: return i18n.t(.sortNewest)
            case .relevance: return i18n.t(.sortRelevance)
            }
        }
    }
    
    private var sortedComments: [YouTubeComment] {
        if commentSortOption == .mostLiked {
            return api.comments.sorted { $0.likeCount > $1.likeCount }
        } else {
            return api.comments
        }
    }

    // Canlı benzeri içerik algısı (kartlardaki ile benzer)
    private var isLiveLike: Bool {
    // Varsayılan: normal video kabul et. Sadece güçlü sinyaller varsa canlı göster.
    // 1) Süre varsa normal video
    if !video.durationText.isEmpty { return false }
    // 2) API canlı izleyici sayısı varsa (servis dolduruyorsa) canlı say
    if let live = api.liveViewersByVideoId[video.id], !live.isEmpty { return true }
    // 3) Başlık veya tarih alanında canlıya açık referanslar
    let title = video.title.lowercased()
    let pub = video.publishedAt.lowercased()
    if title.contains(" live") || title.hasPrefix("live ") || title.contains("canlı") || title.contains(" canlı") { return true }
    if pub.contains("live") || pub.contains("canlı") || pub.contains("yayında") { return true }
    // 4) Sadece metadata eksik diye (viewCount/publishedAt boş) canlıya geçme — placeholder durumlarında yanlış pozitif veriyordu
    return false
    }
    
    // Görüntülenecek metinler: video içinde boşsa yerel fallback kullan
    private var displayedViewCount: String {
        let s = video.viewCount.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? displayViewCountFallback : video.viewCount
    }
    private var displayedPublishedAt: String {
        let s = video.publishedAt.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? displayPublishedAtFallback : video.publishedAt
    }
    // Başlık ve kanal adı için görüntülenecek metinler
    private var displayedTitle: String {
        let raw = video.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty || raw == "Video" { return displayTitleFallback.isEmpty ? (raw.isEmpty ? "Video" : raw) : displayTitleFallback }
        return raw
    }
    private var displayedChannelTitle: String {
        let s = video.channelTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? displayChannelTitleFallback : s
    }
    private var effectiveChannelId: String {
        let s = video.channelId.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? displayChannelIdFallback : s
    }
    
    // MARK: - Helpers (centralized)
    private func sanitizedHTML(_ text: String) -> String { TextUtilities.sanitizedHTML(text) }
    private func attributedWithTimestamps(_ raw: String) -> AttributedString { TextUtilities.linkifiedAttributedString(from: raw) }
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
        VStack(alignment: .leading, spacing: 16) {
            // Title or skeleton
            let needsTitleSkeleton = (video.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || video.title == "Video") && displayTitleFallback.isEmpty
            Group {
                if needsTitleSkeleton {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 420, height: 18)
                        .shimmering()
                        .accessibilityHidden(true)
                } else {
                    Text(displayedTitle)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .lineLimit(nil)
                }
            }
            
            HStack(spacing: 6) {
                if isLiveLike {
                    Circle().fill(Color.red).frame(width: 6, height: 6)
                    if let live = api.liveViewersByVideoId[video.id], !live.isEmpty {
                        Text("\(live) \(i18n.t(.watching))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        Text(i18n.t(.liveBadge))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    // Date skeleton when missing
                    let needsDateSkeleton = video.publishedAt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && displayPublishedAtFallback.isEmpty
                    if !needsDateSkeleton {
                        Text("•")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                            Text(displayedPublishedAt)
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    } else {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.secondary.opacity(0.25))
                            .frame(width: 72, height: 10)
                            .shimmering()
                            .accessibilityHidden(true)
                    }
                } else {
                    // Non-live: views and date with skeletons when missing
                    let needsViewSkeleton = video.viewCount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && displayViewCountFallback.isEmpty
                    let needsDateSkeleton = video.publishedAt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && displayPublishedAtFallback.isEmpty
                    if needsViewSkeleton {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.secondary.opacity(0.25))
                            .frame(width: 80, height: 10)
                            .shimmering()
                            .accessibilityHidden(true)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "eye")
                            Text(displayedViewCount)
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }
                    if !(needsViewSkeleton || needsDateSkeleton) {
                        Text("•")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    if needsDateSkeleton {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.secondary.opacity(0.25))
                            .frame(width: 72, height: 10)
                            .shimmering()
                            .accessibilityHidden(true)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                            Text(displayedPublishedAt)
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }
                }
            }
            
            HStack(spacing: 8) {
                Button(action: {
                    // Kanal paneline geçiş için minimal model oluştur
                    let channel = YouTubeChannel(
                        id: effectiveChannelId,
                        title: displayedChannelTitle,
                        description: api.channelInfo?.description ?? "",
                        thumbnailURL: api.channelInfo?.thumbnailURL ?? video.channelThumbnailURL,
                        subscriberCount: api.channelInfo?.subscriberCount ?? 0,
                        videoCount: api.channelInfo?.videoCount ?? 0
                    )
                    onOpenChannel?(channel)
                }) {
                    HStack(spacing: 8) {
                        AsyncImage(url: URL(string: api.channelInfo?.thumbnailURL ?? video.channelThumbnailURL)) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: { Circle().fill(Color.gray.opacity(0.3)) }
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            let needsChannelNameSkeleton = video.channelTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && displayChannelTitleFallback.isEmpty
                            if needsChannelNameSkeleton {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.secondary.opacity(0.25))
                                    .frame(width: 120, height: 12)
                                    .shimmering()
                                    .accessibilityHidden(true)
                            } else {
                                Text(displayedChannelTitle).font(.headline).foregroundColor(.primary)
                            }
                            if let channelInfo = api.channelInfo, channelInfo.subscriberCount > 0 {
                                Text(channelInfo.formattedSubscriberCount)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else if api.fetchingSubscriberCountIds.contains(effectiveChannelId) || api.fetchingSubscriberCountIds.isEmpty {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.secondary.opacity(0.25))
                                    .frame(width: 52, height: 10)
                                    .shimmering()
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)

                // Subscribe button to the right of channel info
                let isSubscribed = api.isSubscribedToChannel(effectiveChannelId)
                Button(action: {
                    if let channel = api.channelInfo {
                        isSubscribed ? api.unsubscribeFromChannel(channel) : api.subscribeToChannel(channel)
                    } else {
                        let fallback = YouTubeChannel(
                            id: effectiveChannelId,
                            title: displayedChannelTitle,
                            description: "",
                            thumbnailURL: api.channelInfo?.thumbnailURL ?? video.channelThumbnailURL,
                            subscriberCount: api.channelInfo?.subscriberCount ?? 0,
                            videoCount: 0
                        )
                        isSubscribed ? api.unsubscribeFromChannel(fallback) : api.subscribeToChannel(fallback)
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: isSubscribed ? "xmark" : "plus")
                        Text(isSubscribed ? i18n.t(.unsubscribe) : i18n.t(.subscribe))
                            .fontWeight(.semibold)
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(isSubscribed ? Color.secondary.opacity(0.15) : Color.accentColor)
                    )
                    .foregroundColor(isSubscribed ? .primary : .white)
                }
                .buttonStyle(.plain)

                Spacer()
                
                HStack(spacing: 16) {
                    // Like/Dislike combined segmented capsule
                    HStack(spacing: 0) {
                        Button(action: {}) {
                            HStack(spacing: 8) {
                                Image(systemName: "hand.thumbsup").font(.system(size: 18))
                                Text(
                                    api.likeCountByVideoId[video.id]
                                    ?? (Int(video.likeCount.filter({ $0.isNumber })) != nil
                                        ? formatCountShort(video.likeCount.filter({ $0.isNumber }))
                                        : video.likeCount)
                                )
                                .font(.system(size: 14))
                                .lineLimit(1)
                                .fixedSize()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)

                        Rectangle()
                            .fill(Color.white.opacity(0.25))
                            .frame(width: 1, height: 20)
                            .padding(.vertical, 2)

                        Button(action: {}) {
                            HStack(spacing: 8) {
                                Image(systemName: "hand.thumbsdown").font(.system(size: 18))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    .foregroundColor(.primary)
                    .clipShape(Capsule())
                    // Pencere daralsa da beğeni kapsülü aynı görünüme sahip kalsın
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 120)
                    .layoutPriority(2)
                    
                    // Share button with capsule background
                    Button(action: { showShareMenu.toggle() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up").font(.system(size: 18))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                        .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showShareMenu) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(i18n.t(.share)).font(.headline).padding(.bottom, 8)
                            Button(action: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString("https://www.youtube.com/watch?v=\(video.id)", forType: .string)
                                showShareMenu = false
                            }) { HStack { Image(systemName: "doc.on.doc"); Text(i18n.t(.copyLink)) } }
                            .buttonStyle(.plain)
                            Button(action: {
                                if let url = URL(string: "https://www.youtube.com/watch?v=\(video.id)") {
                                    NSWorkspace.shared.open(url)
                                }
                                showShareMenu = false
                            }) { HStack { Image(systemName: "play.rectangle"); Text(i18n.t(.openInYouTube)) } }
                            .buttonStyle(.plain)
                            Divider()
                            Button(i18n.t(.cancel)) { showShareMenu = false }
                                .foregroundColor(.secondary)
                                .buttonStyle(.plain)
                        }
                        .padding()
                        .frame(width: 200)
                    }

                    // Play in Mini (audio-only bottom bar) — right of Share
                    Button(action: {
                        // 1) Mevcut zamanı yakala (son bilinen değer üzerinden de güvence al)
                        let startAt = max(0, getCurrentTime?() ?? 0)
                        // 2) Inline oynatıcıyı tamamen durdur (çift ses önlemek için)
                        NotificationCenter.default.post(name: .stopVideoId, object: nil, userInfo: ["videoId": video.id])
                        // 3) Hedef playlist bağlamını belirle: aktif mini playlist > panel playlist bağlamı > yok
                        let targetPid: String? = {
                            if let pid = audio.activePlaylistId, !pid.isEmpty { return pid }
                            if let ctx = playlistContext { return ctx.playlistId }
                            return nil
                        }()
                        // 4) Mini player'ı başlat ve tam saniyeye sar
                        Task { @MainActor in
                            if let pid = targetPid {
                                // Playlist içinde indeksini bulmayı dene; yoksa 0'dan başla
                                var startIndex = 0
                                if let list = api.cachedPlaylistVideos[pid], let idx = list.firstIndex(where: { $0.id == video.id }) {
                                    startIndex = idx
                                } else if let p = (api.userPlaylists.first(where: { $0.id == pid }) ?? api.searchedPlaylists.first(where: { $0.id == pid })) {
                                    // En az 1 öğe yüklü olsun
                                    await api.ensurePlaylistLoadedCount(playlist: p, minCount: 1)
                                    if let list = api.cachedPlaylistVideos[pid], let idx = list.firstIndex(where: { $0.id == video.id }) { startIndex = idx }
                                }
                                audio.start(playlistId: pid, startIndex: startIndex, using: api, startAtSeconds: startAt, origin: .videoPanel)
                                audio.play()
                            } else {
                                // Tek video kuyruğu oluştur ve başlat
                                audio.startSingle(videoId: video.id, using: api, startAtSeconds: startAt, origin: .videoPanel)
                                audio.play()
                            }
                            // 5) Alt mini çubuğu görünür olsun (start* zaten tetikliyor ama garantiye al)
                            NotificationCenter.default.post(name: .showBottomPlayerBar, object: nil)
                            // 6) Paneli kapat
                            onClosePanel?()
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "play.square.stack").font(.system(size: 18))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                        .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)

                    // Playlist button — opens add-to-playlist popover
                    Button(action: { showPlaylistPopover.toggle() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "music.note.list").font(.system(size: 18))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                        .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showPlaylistPopover) {
                        VStack(alignment: .leading, spacing: 12) {
                            // Existing playlists
                            if api.userPlaylists.isEmpty {
                                Text(i18n.t(.playlists)).font(.headline)
                                Text(i18n.t(.noPlaylistsYet)).foregroundColor(.secondary).font(.subheadline)
                            } else {
                                Text(i18n.t(.playlists)).font(.headline)
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(api.userPlaylists) { p in
                                            HStack {
                                                Text(p.title).lineLimit(1)
                                                Spacer()
                                                Button(action: {
                                                    api.addVideo(video.id, toPlaylistId: p.id)
                                                    showPlaylistPopover = false
                                                    // Show toast for feedback
                                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) { showAddedToast = true }
                                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                                                        withAnimation(.easeInOut(duration: 0.2)) { showAddedToast = false }
                                                    }
                                                }) {
                                                    Image(systemName: "plus.circle")
                                                }.buttonStyle(.plain)
                                            }
                                        }
                                    }
                                }.frame(maxHeight: 180)
                            }
                            Divider()
                            // New playlist section
                            Text(i18n.t(.createNewPlaylist)).font(.headline)
                            HStack(spacing: 8) {
                                // Cover selector (default covers only for now)
                                Menu(content: {
                                    Button("playlist") { tempCoverName = "playlist" }
                                    Button("playlist2") { tempCoverName = "playlist2" }
                                    Button("playlist3") { tempCoverName = "playlist3" }
                                    Button("playlist4") { tempCoverName = "playlist4" }
                                }, label: {
                                    ZStack {
                                        let base = tempCoverName ?? "playlist"
                                        Image(base).resizable().aspectRatio(contentMode: .fill)
                                            .frame(width: 44, height: 28)
                                            .clipped().cornerRadius(4)
                                        RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.4))
                                    }
                                })
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                                TextField(i18n.t(.playlistNamePlaceholder), text: $newPlaylistName)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(minWidth: 160)
                                    .focused($newPlaylistNameFocused)
                            }
                            HStack {
                                Spacer()
                                Button(i18n.t(.cancel)) { showPlaylistPopover = false }
                                    .foregroundColor(.secondary)
                                    .buttonStyle(.plain)
                                Button(i18n.t(.ok)) {
                                    let title = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !title.isEmpty else { return }
                                    if let created = api.createUserPlaylist(title: title, firstVideoId: video.id) {
                                        // If user chose a cover in this popover, apply it
                                        if let name = tempCoverName {
                                            api.setPlaylistCoverName(playlistId: created.id, name: name)
                                        }
                                    }
                                    showPlaylistPopover = false
                                    newPlaylistName = ""
                                    tempCoverName = nil
                                    // Show toast for feedback
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) { showAddedToast = true }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                                        withAnimation(.easeInOut(duration: 0.2)) { showAddedToast = false }
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding()
                        .frame(width: 320)
                        .onAppear { newPlaylistNameFocused = true }
                    }

                    // Yorumları göster/gizle: yalnız ikon, diğerleriyle aynı yükseklik
                    Button(action: {
                    showComments.toggle()
                        if showComments {
                            // İlk açılışta yorumları yükle
                            api.fetchComments(videoId: video.id, append: false, sortOrder: commentSortOption.apiParameter)
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: showComments ? "text.bubble.fill" : "text.bubble")
                                .font(.system(size: 18))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                        .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .onAppear {
                api.fetchLikeCountIfNeeded(videoId: video.id)
                if isLiveLike { api.fetchLiveViewersIfNeeded(videoId: video.id) }
            }
            
            // Description with manual truncation & real expansion
            VStack(alignment: .leading, spacing: 8) {
                // Tüm açıklamayı sanitize et (HTML <br> -> \n, anchor strip vs.) sonra uzunluk / satır hesapla
                let rawDescription = fullDescription ?? video.description
                let sanitizedDescription = sanitizedHTML(rawDescription)
                let trimmed = sanitizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                let endsWithDots = trimmed.hasSuffix("...") || trimmed.hasSuffix("…")
                let lineCount = trimmed.split(separator: "\n").count
                let lengthExceeded = trimmed.count > 300 || lineCount > 6
                let showButton = endsWithDots || lengthExceeded
                // Truncation sanitizasyon SONRASI yapılır ki kesme doğru konumlansın
                let displayedText: String = {
                    guard !isDescriptionExpanded else { return trimmed }
                    if lengthExceeded {
                        let limit = 300
                        if trimmed.count <= limit { return trimmed }
                        var slice = String(trimmed.prefix(limit))
                        if let lastSpace = slice.lastIndex(of: " ") { slice = String(slice[..<lastSpace]) }
                        return slice + "..."
                    }
                    return trimmed
                }()
                // Zaman damgalarını linke çevir (aynı yorumlarda yaptığımız gibi)
                Text(attributedWithTimestamps(displayedText))
                    .font(.body)
                    .environment(\.openURL, OpenURLAction { url in
                        if url.scheme == "ytseek", let secs = Int(url.host ?? url.path.replacingOccurrences(of: "/", with: "")) {
                            NotificationCenter.default.post(name: .seekToSeconds, object: nil, userInfo: ["seconds": secs, "videoId": video.id])
                            return .handled
                        }
                        return .systemAction
                    })
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    // Metin seçimini ve I-beam imlecini devre dışı bırakmak için textSelection kaldırıldı
                #if DEBUG
                // İsteğe göre ayrıntılı debug satırı kaldırıldı.
                #endif
                if isFetchingFullDescription && fullDescription == nil {
                    ProgressView().scaleEffect(0.6)
                }
                if showButton {
                    Button(isDescriptionExpanded ? i18n.t(.showLess) : i18n.t(.readMore)) {
                        withAnimation { isDescriptionExpanded.toggle() }
                        // Açılınca tam açıklamayı zorla getir
                        if isDescriptionExpanded { fetchFullDescriptionIfNeeded(force: true) }
                    }
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(6)
                        .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08))
            )
            .task(id: video.id) {
                // Prefetch (heuristik) – çok kısa ve tek satırsa otomatik getir
                fetchFullDescriptionIfNeeded(force: false)
                await fetchDisplayMetaIfNeeded()
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15))
            )
            
            // Yorumlar bölümü görünürlüğü
            Divider().padding(.vertical, 8)
                .opacity(showComments ? 1 : 0)
                .animation(.easeInOut(duration: 0.15), value: showComments)
            
            // Comments header (yalnızca görünürken)
            if showComments {
                HStack {
                    Text(i18n.t(.comments)).font(.headline)
                    Spacer()
                    Button(action: { showCommentSortMenu.toggle() }) {
                        HStack(spacing: 4) {
                            Image(systemName: commentSortOption.systemImage).font(.system(size: 12))
                            Text(commentSortOption.title(i18n)).font(.system(size: 12, weight: .medium))
                            Image(systemName: "chevron.down").font(.system(size: 10))
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showCommentSortMenu) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(i18n.t(.sortComments)).font(.headline).padding(.bottom, 4)
                            ForEach(CommentSortOption.allCases, id: \.self) { option in
                                Button(action: {
                                    commentSortOption = option
                                    showCommentSortMenu = false
                                    api.fetchComments(videoId: video.id, append: false, sortOrder: option.apiParameter)
                                }) {
                                    HStack {
                                        Image(systemName: option.systemImage)
                                            .foregroundColor(commentSortOption == option ? .accentColor : .secondary)
                                        Text(option.title(i18n))
                                            .foregroundColor(commentSortOption == option ? .accentColor : .primary)
                                        Spacer()
                                        if commentSortOption == option { Image(systemName: "checkmark").foregroundColor(.accentColor) }
                                    }
                                }
                                .buttonStyle(.plain)
                                .padding(.vertical, 2)
                            }
                        }
                        .padding()
                        .frame(width: 180)
                    }
                }
            }
            
            if showComments && sortedComments.isEmpty {
                Text(i18n.t(.comments))
                    .foregroundColor(.secondary)
            } else if showComments {
                ForEach(sortedComments) { comment in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 8) {
                            AsyncImage(url: URL(string: comment.authorImage)) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: { Circle().fill(Color.gray.opacity(0.3)) }
                            .frame(width: 32, height: 32).clipShape(Circle())
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(comment.author).font(.subheadline).fontWeight(.semibold)
                                    HStack(spacing: 4) {
                                        Text(comment.publishedAt).font(.system(size: 11)).foregroundColor(.secondary)
                                        if comment.isPinned { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundColor(.secondary) }
                                    }
                                    Spacer()
                                }
                                
                                let isExpanded = expandedComments.contains(comment.id)
                                let rawText = comment.text
                                let shouldShowReadMore = sanitizedHTML(rawText).count > 200
                                // Text bubble sized to content
                                VStack(alignment: .leading, spacing: 4) {
                                    let display = isExpanded ? sanitizedHTML(rawText) : String(sanitizedHTML(rawText).prefix(200)) + (shouldShowReadMore && !isExpanded ? "..." : "")
                                    Text(attributedWithTimestamps(display))
                                        .font(.body)
                                        .environment(\.openURL, OpenURLAction { url in
                                            if url.scheme == "ytseek", let secs = Int(url.host ?? url.path.replacingOccurrences(of: "/", with: "")) {
                                                NotificationCenter.default.post(name: .seekToSeconds, object: nil, userInfo: ["seconds": secs, "videoId": video.id])
                                                return .handled
                                            }
                                            return .systemAction
                                        })
                                        .fixedSize(horizontal: false, vertical: true)
                                    if shouldShowReadMore {
                                        Button(isExpanded ? i18n.t(.showLess) : i18n.t(.readMore)) {
                                            if isExpanded { expandedComments.remove(comment.id) } else { expandedComments.insert(comment.id) }
                                        }
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.accentColor)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.accentColor.opacity(0.1))
                                        .cornerRadius(4)
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15))
                                )
                                
                                HStack(spacing: 16) {
                                    Button(action: {}) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "hand.thumbsup").font(.system(size: 12))
                                            Text(comment.formattedLikeCount).font(.system(size: 11))
                                        }
                                        .foregroundColor(.secondary)
                                    }.buttonStyle(.plain)
                                    Button(action: {}) {
                                        Image(systemName: "hand.thumbsdown").font(.system(size: 12)).foregroundColor(.secondary)
                                    }.buttonStyle(.plain)
                                    if comment.replyCount > 0 || comment.repliesContinuationToken != nil {
                                        Button(action: {
                                            // Fetch before toggling so first tap opens with data
                                            if comment.replies.isEmpty { api.fetchCommentReplies(commentId: comment.id) }
                                            if expandedReplies.contains(comment.id) { expandedReplies.remove(comment.id) } else { expandedReplies.insert(comment.id) }
                                        }) {
                                            HStack(spacing: 4) {
                                                Image(systemName: expandedReplies.contains(comment.id) ? "arrowtriangle.up" : "arrowtriangle.down").font(.system(size: 10))
                                                Text(i18n.t(.showReplies)).font(.system(size: 11, weight: .medium))
                                            }
                                            .foregroundColor(.secondary)
                                        }.buttonStyle(.plain)
                                    }
                                    Spacer()
                                }
                            }
                        }
                        
                        if !comment.replies.isEmpty && expandedReplies.contains(comment.id) {
                            ForEach(comment.replies) { reply in
                                HStack(alignment: .top, spacing: 8) {
                                    Spacer().frame(width: 20)
                                    AsyncImage(url: URL(string: reply.authorImage)) { image in
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    } placeholder: { Circle().fill(Color.gray.opacity(0.3)) }
                                    .frame(width: 24, height: 24).clipShape(Circle())
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 8) {
                                            Text(reply.author).font(.subheadline).fontWeight(.semibold) // was .caption
                                            Text(reply.publishedAt).font(.system(size: 11)).foregroundColor(.secondary) // align with top-level comment date size
                                            Spacer()
                                        }
                                        let isReplyExpanded = expandedComments.contains(reply.id)
                                        let replyClean = sanitizedHTML(reply.text)
                                        let shouldShowReplyReadMore = replyClean.count > 150
                                        // Reply text bubble sized to content
                                        VStack(alignment: .leading, spacing: 2) {
                                            let replyDisplay = isReplyExpanded ? replyClean : String(replyClean.prefix(150)) + (shouldShowReplyReadMore && !isReplyExpanded ? "..." : "")
                                            Text(attributedWithTimestamps(replyDisplay))
                                                .font(.body) // was .caption
                                                .environment(\.openURL, OpenURLAction { url in
                                                    if url.scheme == "ytseek", let secs = Int(url.host ?? url.path.replacingOccurrences(of: "/", with: "")) {
                                                        NotificationCenter.default.post(name: .seekToSeconds, object: nil, userInfo: ["seconds": secs, "videoId": video.id])
                                                        return .handled
                                                    }
                                                    return .systemAction
                                                })
                                                .fixedSize(horizontal: false, vertical: true)
                                            if shouldShowReplyReadMore {
                                                Button(isReplyExpanded ? i18n.t(.showLess) : i18n.t(.readMore)) {
                                                    if isReplyExpanded { expandedComments.remove(reply.id) } else { expandedComments.insert(reply.id) }
                                                }
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                                .foregroundColor(.accentColor)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 2)
                                                .background(Color.accentColor.opacity(0.1))
                                                .cornerRadius(4)
                                                .buttonStyle(.plain)
                                            }
                                        }
                                        .padding(8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15))
                                        )
                                        
                                        HStack(spacing: 12) {
                                            Button(action: {}) {
                                                HStack(spacing: 2) {
                                                    Image(systemName: "hand.thumbsup").font(.system(size: 10))
                                                    Text(reply.formattedLikeCount).font(.system(size: 9))
                                                }
                                                .foregroundColor(.secondary)
                                            }.buttonStyle(.plain)
                                            Button(action: {}) {
                                                Image(systemName: "hand.thumbsdown").font(.system(size: 10)).foregroundColor(.secondary)
                                            }.buttonStyle(.plain)
                                            Spacer()
                                        }
                                    }
                                }
                                .padding(.leading, 20)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                
                Button(action: {
                    if api.nextCommentsPageToken != nil {
                        api.fetchComments(videoId: video.id, append: true, sortOrder: commentSortOption.apiParameter)
                    }
                }) {
                    HStack {
                        if api.nextCommentsPageToken != nil {
                            Image(systemName: "plus.circle"); Text(i18n.t(.showMoreComments))
                        } else {
                            Image(systemName: "checkmark.circle"); Text(i18n.t(.allCommentsLoaded))
                        }
                    }
                    .font(.subheadline)
                    .foregroundColor(api.nextCommentsPageToken != nil ? .accentColor : .secondary)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(api.nextCommentsPageToken != nil ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.1))
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(api.nextCommentsPageToken == nil)
            }
        }
        .onAppear {
            api.fetchVideoDetails(videoId: video.id)
            // İlk girişte like sözlüğünde değer yoksa video.likeCount içindeki rakamları kısaltıp gösterelim
            if api.likeCountByVideoId[video.id] == nil {
                let digits = video.likeCount.filter { $0.isNumber }
                if let val = Int(digits), val > 0 { // sadece >0 ise önceden göster
                    api.likeCountByVideoId[video.id] = formatCountShort(digits)
                }
            }
            // Eğer hâlâ yoksa veya 0 ise aktif fetch'i zorla
            api.fetchLikeCountIfNeeded(videoId: video.id)
            if isLiveLike { api.fetchLiveViewersIfNeeded(videoId: video.id) }
        }
        // Toggle değişince (true olduğunda) yorumları yükle
    .onChange(of: showComments) { _, newVal in
            if newVal {
                api.fetchComments(videoId: video.id, append: false, sortOrder: commentSortOption.apiParameter)
            }
        }
        }
        .overlay(alignment: .topTrailing) { toastOverlay() }
    }
}

// MARK: - Full Description Fetch
private extension LeftVideoContentView {
    func fetchFullDescriptionIfNeeded(force: Bool) {
        // Yeni mantık: Açıklama genişletildiğinde her zaman (bir kez) uzun açıklamayı dene.
        guard fullDescription == nil, !isFetchingFullDescription else { return }
        isFetchingFullDescription = true
    _ = video.description.count // preserve prior debug trigger without unused warning
        #if DEBUG
    // 1 = tetikleme
    print("1")
        #endif
    Task { [videoId = video.id] in
            #if DEBUG
        // (İstenirse burada ek marker eklenebilir.)
            #endif
            do {
                let data = try await api.fetchVideoMetadata(videoId: videoId)
                await MainActor.run {
                    #if DEBUG
            // 2 = başarı
            print("2")
                    #endif
                    self.fullDescription = data.effectiveDescription
                    self.isFetchingFullDescription = false
                }
            } catch {
                await MainActor.run {
                    #if DEBUG
            // 2e = hata
            print("2e")
                    #endif
                    self.isFetchingFullDescription = false
                }
            }
        }
    }
    
    // Playlist modunda başlangıçta viewCount/publishedAt boş gelebilir; panelde yerel meta ile doldur.
    func fetchDisplayMetaIfNeeded() async {
        let needsView = video.viewCount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let needsDate = video.publishedAt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let needsTitle = video.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || video.title == "Video"
        let needsChannelTitle = video.channelTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let needsChannelId = video.channelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // Eğer ikisi de doluysa gereksiz network yok
        guard needsView || needsDate || needsTitle || needsChannelTitle || needsChannelId else { return }
        do {
            // Fetch with current locale parameters
            let locale = api.currentLocaleParams()
            let meta = try await api.fetchVideoMetadata(videoId: video.id, hl: locale.hl, gl: locale.gl)
            await MainActor.run {
                if needsView { self.displayViewCountFallback = meta.viewCountText }
                if needsDate { self.displayPublishedAtFallback = meta.publishedTimeText }
                if needsTitle { self.displayTitleFallback = meta.title }
                if needsChannelTitle { self.displayChannelTitleFallback = meta.author }
                if needsChannelId, let cid = meta.channelId { self.displayChannelIdFallback = cid }
                // Eğer API kanal bilgisi boş ve elimizde güvenilir bir kanalId varsa, abone sayısı/thumbnail için fetch başlat
                if self.api.channelInfo == nil {
                    let cid = !self.video.channelId.isEmpty ? self.video.channelId : (self.displayChannelIdFallback)
                    if !cid.isEmpty { self.api.fetchChannelInfo(channelId: cid) }
                }
            }
        } catch {
            // Sessiz geç – panel boş string göstermeye devam eder, cache zenginleşince onChange tetiklenir
        }
    }
}

extension Notification.Name {
    static let seekToSeconds = Notification.Name("seekToSeconds")
}

// MARK: - Overlay (Toast)
extension LeftVideoContentView {
    @ViewBuilder
    private func toastOverlay() -> some View {
        ZStack(alignment: .topTrailing) {
            if showAddedToast {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text(i18n.t(.addedToPlaylistToast))
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    ZStack {
                        VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                        RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.1))
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.top, 8)
                .padding(.trailing, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}
