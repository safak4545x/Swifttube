
/*
 Overview / Genel Bakış
 EN: Playlist search UI with ability to import and view playlists; supports CSV drag & drop import.
 TR: Playlist arama arayüzü; playlist içe aktarma ve görüntülemeyi destekler; CSV sürükle-bırak ile içe aktarım yapar.
*/

// EN: SwiftUI for UI; UTType for CSV drag & drop. TR: UI için SwiftUI; CSV sürükle-bırak için UTType.
import SwiftUI
import UniformTypeIdentifiers

// EN: Shows playlists page/search with optional header and import. TR: Başlık ve içe aktarma seçenekli playlist sayfası/araması.
struct PlaylistSearchView: View {
    // EN: i18n provider. TR: i18n sağlayıcı.
    @EnvironmentObject var i18n: Localizer
    // EN: Dismiss handle for sheet usage. TR: Sheet kullanımı için kapatma tutamacı.
    @Environment(\.dismiss) private var dismiss
    // EN: API service driving playlists. TR: Playlist’leri yöneten API servisi.
    @ObservedObject var youtubeAPI: YouTubeAPIService
    // EN: Current query text. TR: Geçerli sorgu metni.
    @State private var searchText = ""
    // EN: Selection bindings to open playlist view. TR: Playlist görünümünü açmak için seçim binding'leri.
    @Binding var selectedPlaylist: YouTubePlaylist?
    @Binding var showPlaylistView: Bool
    // EN: When true, renders search header; when false, acts as Playlists page. TR: true iken arama başlığı var; false iken Playlists sayfası gibi davranır.
    var showHeader: Bool = true
    // EN: Import modal toggle. TR: İçe aktarma modal anahtarı.
    @State private var showingImportPanel = false
    // EN: Drag highlight for Auto Import chip. TR: Otomatik İçe Aktar çipi için sürükleme vurgusu.
    @State private var isImportTargeted = false
    // EN: Ensure a single expanded playlist at a time. TR: Aynı anda tek genişletilmiş playlist.
    @State private var openPlaylistId: String? = nil
    // EN: Lock outer scrolling when inner panel is active. TR: İç panel aktifken dış kaydırmayı kilitle.
    @State private var disableOuterScroll: Bool = false
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
            // EN: Optional search header for the sheet mode. TR: Sheet modunda opsiyonel arama başlığı.
            if showHeader {
                HStack {
            TextField(i18n.t(.playlists) + " " + i18n.t(.search).lowercased() + "...", text: $searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onSubmit {
                let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !q.isEmpty else { return }
                youtubeAPI.searchPlaylists(query: q)
                        }

                    Button(i18n.t(.search)) {
                        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !q.isEmpty else { return }
                        youtubeAPI.searchPlaylists(query: q)
                    }
                    .buttonStyle(.borderedProminent)

                    Spacer()
                }
                .padding()
            }
            
            // EN: Results area (loading, local grid, or searched list). TR: Sonuç alanı (yükleme, yerel ızgara veya arama listesi).
            if youtubeAPI.isSearching {
                ProgressView(i18n.t(.search) + "...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // EN: Header title for Playlists page variant. TR: Playlists sayfası varyantı için başlık.
                        if !showHeader {
                            HStack {
                                Text(i18n.t(.playlists))
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.primary)
                                Spacer()
                                // EN: Auto Import button floats; header stays simple. TR: Otomatik İçe Aktar butonu yüzer; başlık sade kalır.
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 12)
                        }
                        // EN: Local user playlists grid (Playlists page only). TR: Yerel kullanıcı playlist ızgarası (yalnız Playlists sayfasında).
                        if !showHeader && !youtubeAPI.userPlaylists.isEmpty {
                            // EN: Slightly wider cards for readability. TR: Okunabilirlik için kartları biraz genişlet.
                            let columns = [
                                GridItem(
                                    .adaptive(minimum: 340, maximum: 480),
                                    spacing: 12,
                                    alignment: .top
                                )
                            ]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                                ForEach(youtubeAPI.userPlaylists) { playlist in
                    PlaylistView(youtubeAPI: youtubeAPI, playlist: playlist, openPlaylistId: $openPlaylistId, disableOuterScroll: $disableOuterScroll)
                                        .environmentObject(i18n)
                                }
                            }
                            .padding(.horizontal, 24)
                        }

                        // EN: Searched playlists only in sheet mode. TR: Aranan playlist'ler yalnızca sheet modunda.
                        if showHeader {
                            if !youtubeAPI.searchedPlaylists.isEmpty {
                                Text(i18n.t(.sectionSearchResults))
                                    .font(.headline)
                                    .padding(.top, 8)
                                    .padding(.horizontal)
                                LazyVStack(spacing: 12) {
                                    ForEach(youtubeAPI.searchedPlaylists) { playlist in
                                        PlaylistView(youtubeAPI: youtubeAPI, playlist: playlist, isSearchResult: true, openPlaylistId: $openPlaylistId, disableOuterScroll: $disableOuterScroll)
                                            .environmentObject(i18n)
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.bottom)
                            } else if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                // EN: Empty state after a non-empty query. TR: Boş olmayan sorgudan sonra boş durum.
                                Text(i18n.t(.sectionSearchResults))
                                    .font(.headline)
                                    .padding(.top, 8)
                                    .padding(.horizontal)
                                Text("No playlists found.")
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal)
                                    .padding(.bottom)
                            }
                        }
                    }
                }
                .scrollDisabled(disableOuterScroll)
            }
            }
            // EN: Floating Auto Import chip when header hidden (Playlists page). TR: Başlık gizliyken yüzen Otomatik İçe Aktar çipi (Playlists sayfası).
            if !showHeader {
                Button(action: { showingImportPanel = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 14))
                        Text(i18n.t(.autoImport))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.green.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(isImportTargeted ? Color.green : Color.clear, lineWidth: 2)
                            )
                    )
                }
                .buttonStyle(.plain)
                .onDrop(of: [UTType.fileURL], isTargeted: $isImportTargeted) { providers in
                    // EN: Highlight and handle CSV drop on the chip. TR: Çip üzerinde CSV bırakmayı vurgula ve işle.
                    handleCSVDrop(providers: providers)
                }
                .padding(.top, 10)
                .padding(.trailing, 12)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        // Allow dropping CSV anywhere in the page to import (only on playlists panel)
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            // EN: Disable page-wide drop when in sheet mode. TR: Sheet modundayken sayfa geneli bırakmayı kapat.
            guard !showHeader else { return false }
            return handleCSVDrop(providers: providers)
        }
        .sheet(isPresented: $showingImportPanel) {
            // EN: File chooser for CSV import. TR: CSV içe aktarımı için dosya seçici.
            PlaylistCSVImportView(youtubeAPI: youtubeAPI, isPresented: $showingImportPanel)
        }
        // When user starts playback from the search results, close the search panel immediately
        .onReceive(NotificationCenter.default.publisher(for: .openPlaylistModeOverlay)) { _ in
            // EN: Close search sheet on overlay open. TR: Panel açılınca arama sheet’ini kapat.
            if showHeader { dismiss() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openPlaylistMode)) { _ in
            // EN: Close search sheet on playlist mode open. TR: Playlist modu açılınca arama sheet’ini kapat.
            if showHeader { dismiss() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .startAudioPlaylist)) { _ in
            // EN: Close search sheet on audio playlist start. TR: Ses playlisti başlayınca arama sheet’ini kapat.
            if showHeader { dismiss() }
        }
    }
}

// MARK: - CSV Drop Handling
extension PlaylistSearchView {
    private func handleCSVDrop(providers: [NSItemProvider]) -> Bool {
        // EN: Only allow drop-import on the Playlists page, not in sheet mode. TR: İçe aktarmayı sadece Playlists sayfasında (sheet değil) etkinleştir.
    if showHeader { return false }
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, error in
            guard let url = url else { return }
            if url.pathExtension.lowercased() == "csv" {
                if let content = try? String(contentsOf: url, encoding: .utf8) {
                    // EN: Robust parse: scan all fields in each line for URL/ID tokens. TR: Dayanıklı çözümleme: her satırda URL/ID belirteçlerini tara.
                    let tokens = robustCSVTokenize(content: content)
                    // EN: Inject filename token to use as playlist name. TR: Dosya adını playlist adı olarak kullanmak için belirteç ekle.
                    let filename = url.deletingPathExtension().lastPathComponent
                    let payload = ["__CSV_FILENAME__=\(filename)"] + tokens
                    DispatchQueue.main.async { youtubeAPI.importPlaylists(from: payload) }
                }
            }
        }
        return true
    }

    /// EN: Extract playlist/video tokens from CSV safely.
    /// TR: CSV içeriğinden playlist/video belirteçlerini güvenli çıkar.
    /// EN: Algorithm: split by ; , or tab; then scan fields for:
    ///  - YouTube URL (if contains "youtu")
    ///  - Playlist ID (prefix PL/LL/UU/OL/FL/WL/RD)
    ///  - Video ID (11 chars, [A-Za-z0-9_-]{11})
    private func robustCSVTokenize(content: String) -> [String] {
        var out = Set<String>()
        let lines = content.components(separatedBy: .newlines)
        let delimiters: CharacterSet = CharacterSet(charactersIn: ",;\t")
        let idRegex = try? NSRegularExpression(pattern: "^[A-Za-z0-9_-]{11}$", options: [])
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            let fields = line.components(separatedBy: delimiters)
            for f in fields {
                var token = f.trimmingCharacters(in: .whitespacesAndNewlines)
                token = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if token.isEmpty { continue }
                let lower = token.lowercased()
                // EN: Keep YouTube URLs verbatim (upstream will normalize). TR: YouTube URL'leri doğrudan ekle (yukarıda normalize edilir).
                if lower.contains("youtu.be") || lower.contains("youtube.com") {
                    out.insert(token)
                    continue
                }
                // EN: Playlist ID pattern check. TR: Playlist ID deseni kontrolü.
                if token.count >= 2 {
                    let prefixes = ["PL","LL","UU","OL","FL","RD"]
                    if prefixes.contains(where: { token.hasPrefix($0) }) || token == "WL" {
                        out.insert(token)
                        continue
                    }
                }
                // EN: Video ID of 11 chars via regex. TR: Regex ile 11 karakterlik video ID.
                if token.count == 11, let re = idRegex {
                    let ns = token as NSString
                    if re.firstMatch(in: token, range: NSRange(location: 0, length: ns.length)) != nil {
                        out.insert(token)
                        continue
                    }
                }
            }
        }
        return Array(out)
    }
}
