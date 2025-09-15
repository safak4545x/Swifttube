/*
 File Overview (EN)
 Purpose: Shorts page rendering a vertical, swipeable experience for short-form videos with optional comments overlay and controls.
 Key Responsibilities:
 - Display shorts feed and handle current index
 - Integrate ShortsPlayerView for playback and controls (mute, repeat)
 - Optionally show/hide comments panel for the active short
 Used By: MainContentView when Shorts is selected.

 Dosya Özeti (TR)
 Amacı: Kısa videolar için dikey, kaydırılabilir deneyim sunan Shorts sayfası; yorum katmanı ve kontrollerle birlikte.
 Ana Sorumluluklar:
 - Shorts akışını göstermek ve aktif indeksi yönetmek
 - Oynatma ve kontroller için ShortsPlayerView ile bütünleşmek (sessiz, tekrar vb.)
 - Aktif kısa için yorum panelini isteğe bağlı göster/gizle
 Nerede Kullanılır: MainContentView’de Shorts seçiliyken.
*/

import SwiftUI
import AppKit

struct ShortsView: View {
    @EnvironmentObject var i18n: Localizer
    @ObservedObject var youtubeAPI: YouTubeAPIService
    @Binding var showShortsComments: Bool
    @Binding var currentShortsIndex: Int

    @State private var shouldPlayCurrent = true
    @State private var keyMonitor: Any?
    @State private var wheelMonitor: Any?
    @State private var isHandlingScroll = false
    @State private var isHoveringVideoArea = false
    @State private var isHoveringCommentsPanel = false
    @State private var lastShortsIndex: Int? = nil

    // MARK: - Navigation Helpers
    private func clampIndex(_ idx: Int) -> Int {
        guard !youtubeAPI.shortsVideos.isEmpty else { return 0 }
        return min(max(0, idx), youtubeAPI.shortsVideos.count - 1)
    }

    private func navigate(to newIndex: Int) {
        guard !youtubeAPI.shortsVideos.isEmpty else { return }
        let clamped = clampIndex(newIndex)
        guard clamped != currentShortsIndex else { return }
        currentShortsIndex = clamped
    }

    private func navigateNext() { navigate(to: currentShortsIndex + 1) }
    private func navigatePrev() { navigate(to: currentShortsIndex - 1) }

    var body: some View {
        HStack(spacing: 0) {
            // Video bölümü (sol taraf)
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 40) { // boşluk ver ki alt video hafif görünür
                            if youtubeAPI.shortsVideos.isEmpty {
                                VStack(spacing: 12) {
                                    if youtubeAPI.isLoading {
                                        ProgressView().scaleEffect(1.5)
                                        Text(i18n.t(.loadingShorts))
                                            .foregroundColor(.white)
                                    } else {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.system(size: 30))
                                            .foregroundColor(.yellow)
                                        Text(i18n.t(.noShortsFound))
                                            .multilineTextAlignment(.center)
                                            .foregroundColor(.white.opacity(0.85))
                                            .frame(maxWidth: 300)
                                        Button(i18n.t(.reload)) { youtubeAPI.fetchShortsVideos(suppressOverlay: false, forceRefresh: true) }
                                            .buttonStyle(.borderedProminent)
                                    }
                                }
                                .padding(.top, 60)
                                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                            } else {
                                ForEach(Array(youtubeAPI.shortsVideos.enumerated()), id: \.offset) { index, video in
                                    // En büyük sığan 9:16 boyut: hem genişlik hem yükseklik büyüdükçe artsın, sola yapışık
                                    let maxW = geometry.size.width * 0.9 // solda biraz margin
                                    let maxH = geometry.size.height * 0.95
                                    // İki sınıra göre en büyük boyut: önce genişliğe göre yükseklik, sonra yüksekliğe göre genişlik karşılaştır
                                    let widthFromHeight = maxH * 9/16
                                    let heightFromWidth = maxW * 16/9
                                    let useHeightConstraint = widthFromHeight <= maxW
                                    let finalWidth = useHeightConstraint ? widthFromHeight : maxW
                                    let finalHeight = useHeightConstraint ? maxH : heightFromWidth
                                    ShortsVideoView(
                                        video: video,
                                        youtubeAPI: youtubeAPI,
                                        showComments: $showShortsComments,
                                        shouldPlay: Binding(
                                            get: { index == currentShortsIndex ? shouldPlayCurrent : false },
                                            set: { newVal in if index == currentShortsIndex { shouldPlayCurrent = newVal } }
                                        )
                                    )
                                    .frame(width: finalWidth, height: finalHeight)
                                    .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .center) // ortala
                                    .contentShape(Rectangle())
                                    .id(index)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .scrollDisabled(true) // Kendi geçişimizi yönetiyoruz (snap)
                    .onChange(of: currentShortsIndex) { _, newIndex in
                        print("➡️ Shorts index changed ->", newIndex)
                        // Önceki videonun player'ını tamamen serbest bırak (reset)
                        if let old = lastShortsIndex, youtubeAPI.shortsVideos.indices.contains(old) {
                            let oldId = youtubeAPI.shortsVideos[old].id
                            NotificationCenter.default.post(name: .shortsResetVideoId, object: nil, userInfo: ["videoId": oldId])
                        }
                        // Komşu (üst ve alt) videoları da proaktif durdur (kaydırma hızında çifte tetiklenmeyi engelle)
                        let neighbors = [newIndex - 1, newIndex + 1]
                        for n in neighbors where youtubeAPI.shortsVideos.indices.contains(n) {
                            let vid = youtubeAPI.shortsVideos[n].id
                            NotificationCenter.default.post(name: .shortsResetVideoId, object: nil, userInfo: ["videoId": vid])
                        }
                        withAnimation(.easeInOut(duration: 0.22)) {
                            proxy.scrollTo(newIndex, anchor: .top)
                        }
                        // Odağı tüm oynatıcılara yayınla
                        if youtubeAPI.shortsVideos.indices.contains(newIndex) {
                            NotificationCenter.default.post(name: .shortsFocusVideoId, object: nil, userInfo: ["videoId": youtubeAPI.shortsVideos[newIndex].id])
                        } else {
                            print("⚠️ Attempted focus post for invalid index \(newIndex) total=\(youtubeAPI.shortsVideos.count)")
                        }
                        // Sadece mevcut index için oynatmayı aç
                        shouldPlayCurrent = true
                        // Yorum paneli açıksa yeni videonun yorumlarını getir
                        if showShortsComments, youtubeAPI.shortsVideos.indices.contains(newIndex) {
                            youtubeAPI.fetchComments(videoId: youtubeAPI.shortsVideos[newIndex].id, append: false, sortOrder: LeftVideoContentView.CommentSortOption.relevance.apiParameter)
                        }
                        // Son index'i güncelle
                        lastShortsIndex = newIndex
                    }
                    .onAppear {
                        // Shorts videolarını yükle (aynı anda ikinci kez tetiklemeyi engelle)
                        if youtubeAPI.shortsVideos.isEmpty && !youtubeAPI.isLoading {
                            print("🚀 ShortsView onAppear -> fetching shorts")
                            youtubeAPI.fetchShortsVideos(suppressOverlay: false, forceRefresh: true)
                        } else {
                            print("ℹ️ ShortsView onAppear -> reuse existing shorts count=\(youtubeAPI.shortsVideos.count) loading=\(youtubeAPI.isLoading)")
                        }
                        // İlk konuma git
                        DispatchQueue.main.async {
                            proxy.scrollTo(currentShortsIndex, anchor: .top)
                        }
                        // Başlangıç index'ini kaydet
                        lastShortsIndex = currentShortsIndex
                        // Klavye: space play/pause, up/down gezinme
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                            // Eğer bir metin alanında yazım yapılıyorsa (ör. arama kutusu),
                            // bu kısayolları tüketmeyip event'i olduğu gibi ilet.
                            if let fr = NSApp.keyWindow?.firstResponder, fr is NSTextView {
                                return event
                            }
                            // Command (⌘) ile kullanılan kısayolları da bırak (uygulama genel kısayolları).
                            if event.modifierFlags.contains(.command) {
                                return event
                            }
                            switch event.keyCode {
                            case 49: // space
                                shouldPlayCurrent.toggle()
                                NotificationCenter.default.post(name: .userInteractedWithShorts, object: nil)
                                return nil
                            case 126: // up
                print("⬆️ Key up pressed")
                navigatePrev()
                                NotificationCenter.default.post(name: .userInteractedWithShorts, object: nil)
                                return nil
                            case 125: // down
                print("⬇️ Key down pressed")
                navigateNext()
                                NotificationCenter.default.post(name: .userInteractedWithShorts, object: nil)
                                return nil
                            default:
                                return event
                            }
                        }
                        // Mouse tekerleğiyle tek adımlı (snap) navigation - sadece video alanı üzerindeyken
            wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { ev in
                // Yorum paneli üzerindeysek event'i bırak (yorumlar kendi ScrollView'unda kayacak)
                if showShortsComments && isHoveringCommentsPanel { return ev }
                // Video alanı üzerinde değilsek veya şu an bekleme süresindeysek bırak
                if !isHoveringVideoArea || isHandlingScroll { return ev }
                let dy = ev.scrollingDeltaY
                if dy == 0 { return ev }
                isHandlingScroll = true
                defer {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { isHandlingScroll = false }
                }
                if dy > 0 { navigatePrev() } else { navigateNext() }
                print("🖱️ Scroll deltaY=\(dy) -> currentShortsIndex=\(currentShortsIndex)")
                NotificationCenter.default.post(name: .userInteractedWithShorts, object: nil)
                return nil // navigasyonu biz yönettik
            }
                        // Başlangıç odak bildirimi
                        if youtubeAPI.shortsVideos.indices.contains(currentShortsIndex) {
                            NotificationCenter.default.post(name: .shortsFocusVideoId, object: nil, userInfo: ["videoId": youtubeAPI.shortsVideos[currentShortsIndex].id])
                        }
                    }
                    // Pencere yeniden boyutlanınca mevcut öğeye sabitleyerek dikey kaymayı engelle
                    .onChange(of: geometry.size) { _, _ in
                        DispatchQueue.main.async {
                            withAnimation(.none) { proxy.scrollTo(currentShortsIndex, anchor: .top) }
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .shortsRequestNext)) { _ in
                        print("📩 Received .shortsRequestNext")
                        navigateNext()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .shortsRequestPrev)) { _ in
                        print("📩 Received .shortsRequestPrev")
                        navigatePrev()
                    }
                    .onDisappear {
                        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
                        keyMonitor = nil
                        if let monitor = wheelMonitor { NSEvent.removeMonitor(monitor) }
                        wheelMonitor = nil
                        // Sayfadan çıkarken tüm Shorts player'larını tamamen durdur ve serbest bırak
                        NotificationCenter.default.post(name: .shortsStopAll, object: nil)
                        NotificationCenter.default.post(name: .stopAllVideos, object: nil)
                        // Bir dahaki girişte temiz başlangıç için oynatma state'ini kapat
                        shouldPlayCurrent = false
                        lastShortsIndex = nil
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .background(
                // Arkaplanda: mevcut Shorts videosunun küçük görselinden üretilmiş blur, kenarlara doğru solan maske ile
                GeometryReader { bgGeo in
                    ZStack {
                        Color.black // taban
                        if youtubeAPI.shortsVideos.indices.contains(currentShortsIndex) {
                            let bgVideo = youtubeAPI.shortsVideos[currentShortsIndex]
                            CachedAsyncImage(url: URL(string: bgVideo.thumbnailURL)) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: bgGeo.size.width, height: bgGeo.size.height)
                                    .clipped()
                                    .blur(radius: 40)
                                    .saturation(0.95)
                                    .overlay(Color.black.opacity(0.25)) // az karartma
                                    .mask(
                                        // Video alanının etrafında yumuşak geçişli bir maske: tüm ekranı kaplamasın
                                        ZStack {
                                            // Video boyutunu yaklaşık hesapla (9:16 oran, mevcut layout ile uyumlu)
                                            let maxW = bgGeo.size.width * 0.9
                                            let maxH = bgGeo.size.height * 0.95
                                            let widthFromHeight = maxH * 9/16
                                            let useHeightConstraint = widthFromHeight <= maxW
                                            let finalWidth = useHeightConstraint ? widthFromHeight : maxW
                                            let finalHeight = useHeightConstraint ? maxH : (maxW * 16/9)

                                            // Video dikdörtgenini biraz büyütüp blur'layarak kenarlara doğru soluklaştır
                                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                                .fill(Color.white)
                                                .frame(width: finalWidth + 260, height: finalHeight + 260)
                                                .blur(radius: 90)
                                                .opacity(1)
                                        }
                                    )
                            } placeholder: {
                                Color.clear
                            }
                            .transition(.opacity)
                        }
                    }
                }
            )
            .onHover { hovering in
                isHoveringVideoArea = hovering
            }

            // Yorumlar bölümü (sağ taraf)
            if showShortsComments {
                ShortsCommentsPanel(youtubeAPI: youtubeAPI, showShortsComments: $showShortsComments, currentShortsIndex: $currentShortsIndex)
                    .background(Color(NSColor.controlBackgroundColor))
                    .onHover { hovering in
                        isHoveringCommentsPanel = hovering
                    }
            }
        }
    }
}

// MARK: - Shorts Comments Panel (normal video ile aynı deneyim)
private struct ShortsCommentsPanel: View {
    @EnvironmentObject var i18n: Localizer
    @ObservedObject var youtubeAPI: YouTubeAPIService
    @Binding var showShortsComments: Bool
    @Binding var currentShortsIndex: Int
    @State private var showSortMenu = false
    @State private var sortOption: LeftVideoContentView.CommentSortOption = .relevance
    @State private var expandedComments: Set<String> = []
    @State private var expandedReplies: Set<String> = []

    // HTML -> plain text (Shorts yorumları için). <br> satır sonuna çevrilir; diğer tag'lar temizlenir.
    private func sanitizedHTML(_ text: String) -> String { TextUtilities.sanitizedHTML(text) }

    private var sortedComments: [YouTubeComment] {
        if sortOption == .mostLiked { return youtubeAPI.comments.sorted { $0.likeCount > $1.likeCount } }
        return youtubeAPI.comments
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(i18n.t(.comments)).font(.headline)
                Spacer()
                Button(action: { showSortMenu.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: sortOption.systemImage).font(.system(size: 12))
                        Text(sortOption.title(i18n)).font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.down").font(.system(size: 10))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showSortMenu) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(i18n.t(.sortComments)).font(.headline).padding(.bottom, 4)
                        ForEach(LeftVideoContentView.CommentSortOption.allCases, id: \.self) { option in
                            Button(action: {
                                sortOption = option
                                showSortMenu = false
                                if youtubeAPI.shortsVideos.indices.contains(currentShortsIndex) {
                                    youtubeAPI.fetchComments(videoId: youtubeAPI.shortsVideos[currentShortsIndex].id, append: false, sortOrder: option.apiParameter)
                                }
                            }) {
                                HStack {
                                    Image(systemName: option.systemImage)
                                        .foregroundColor(sortOption == option ? .accentColor : .secondary)
                                    Text(option.title(i18n))
                                        .foregroundColor(sortOption == option ? .accentColor : .primary)
                                    Spacer()
                                    if sortOption == option { Image(systemName: "checkmark").foregroundColor(.accentColor) }
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 2)
                        }
                    }
                    .padding()
                    .frame(width: 180)
                }
                Button(action: { showShortsComments = false }) {
                    Image(systemName: "xmark").font(.system(size: 16)).foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.thinMaterial)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(sortedComments) { comment in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 8) {
                                CachedAsyncImage(url: URL(string: comment.authorImage)) { image in
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } placeholder: { Circle().fill(Color.gray.opacity(0.3)) }
                                .frame(width: 28, height: 28)
                                .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        Text(comment.author).font(.subheadline).fontWeight(.semibold)
                                        Text(comment.publishedAt).font(.system(size: 11)).foregroundColor(.secondary)
                                        if comment.isPinned { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundColor(.secondary) }
                                        Spacer()
                                    }
                                    let clean = sanitizedHTML(comment.text)
                                    let isExpanded = expandedComments.contains(comment.id)
                                    let limit = 160
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(.init(isExpanded ? clean : (clean.count > limit ? String(clean.prefix(limit)) + "..." : clean)))
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .padding(10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15))
                                    )
                                    if clean.count > limit {
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

                                    HStack(spacing: 14) {
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
                                                if comment.replies.isEmpty { youtubeAPI.fetchCommentReplies(commentId: comment.id) }
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
                                        CachedAsyncImage(url: URL(string: reply.authorImage)) { image in
                                            image.resizable().aspectRatio(contentMode: .fill)
                                        } placeholder: { Circle().fill(Color.gray.opacity(0.3)) }
                                        .frame(width: 22, height: 22).clipShape(Circle())

                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack(spacing: 8) {
                                                Text(reply.author).font(.caption).fontWeight(.semibold)
                                                Text(reply.publishedAt).font(.system(size: 10)).foregroundColor(.secondary)
                                                Spacer()
                                            }
                                            let replyLimit = 140
                                            let replyText = sanitizedHTML(reply.text)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(.init(replyText.count > replyLimit ? String(replyText.prefix(replyLimit)) + "..." : replyText))
                                                    .fixedSize(horizontal: false, vertical: true)
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
                        .padding(.horizontal, 16)
                    }

                    Button(action: {
                        if youtubeAPI.nextCommentsPageToken != nil,
                           youtubeAPI.shortsVideos.indices.contains(currentShortsIndex) {
                            youtubeAPI.fetchComments(videoId: youtubeAPI.shortsVideos[currentShortsIndex].id, append: true, sortOrder: sortOption.apiParameter)
                        }
                    }) {
                        HStack {
                            if youtubeAPI.nextCommentsPageToken != nil {
                                Image(systemName: "plus.circle"); Text(i18n.t(.showMoreComments))
                            } else {
                                Image(systemName: "checkmark.circle"); Text(i18n.t(.allCommentsLoaded))
                            }
                        }
                        .font(.subheadline)
                        .foregroundColor(youtubeAPI.nextCommentsPageToken != nil ? .accentColor : .secondary)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(youtubeAPI.nextCommentsPageToken != nil ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.1))
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(youtubeAPI.nextCommentsPageToken == nil)
                    .padding(.top, 8)
                }
                .padding(.vertical, 12)
            }
        }
        .frame(width: 340)
    .background(Color(NSColor.controlBackgroundColor))
        .onAppear {
            if youtubeAPI.shortsVideos.indices.contains(currentShortsIndex) {
                youtubeAPI.fetchComments(videoId: youtubeAPI.shortsVideos[currentShortsIndex].id, append: false, sortOrder: sortOption.apiParameter)
            }
        }
    .onChange(of: currentShortsIndex) { _, newIndex in
            // Panel açıkken video değişti; durumları sıfırla ve yeni yorumları çek
            expandedComments.removeAll()
            expandedReplies.removeAll()
            if youtubeAPI.shortsVideos.indices.contains(newIndex) {
                youtubeAPI.fetchComments(videoId: youtubeAPI.shortsVideos[newIndex].id, append: false, sortOrder: sortOption.apiParameter)
            }
        }
    }
}
