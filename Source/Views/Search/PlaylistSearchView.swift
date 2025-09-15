
/*
 File Overview (EN)
 Purpose: Search UI for playlists with ability to add searched playlists to user library and open details.
 Key Responsibilities:
 - Bind to playlist search results and show via PlaylistRowView
 - Add to user playlists and open PlaylistView
 Used By: MainContentView toolbar action (search playlist).

 Dosya Özeti (TR)
 Amacı: Çalma listeleri için arama arayüzü; aranan playlist'i kullanıcı kütüphanesine ekleme ve detay açma.
 Ana Sorumluluklar:
 - Playlist arama sonuçlarına bağlanıp PlaylistRowView ile göstermek
 - Kullanıcı playlist'lerine eklemek ve PlaylistView'i açmak
 Nerede Kullanılır: MainContentView araç çubuğu (playlist ara) eylemi.
*/

import SwiftUI
import UniformTypeIdentifiers

struct PlaylistSearchView: View {
    @EnvironmentObject var i18n: Localizer
    // Dismiss to close when used as a sheet (playlist search panel)
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var youtubeAPI: YouTubeAPIService
    @State private var searchText = ""
    @Binding var selectedPlaylist: YouTubePlaylist?
    @Binding var showPlaylistView: Bool
    var showHeader: Bool = true
    @State private var showingImportPanel = false
    // Drag-highlight for Auto Import pill (CSV drop)
    @State private var isImportTargeted = false
    // Tek açık playlist kontrolü
    @State private var openPlaylistId: String? = nil
    // Alt panel üzerindeyken sayfa kaydırmasını kilitle
    @State private var disableOuterScroll: Bool = false
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
            // Optional Search Header
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
            
            // Search Results
            if youtubeAPI.isSearching {
                ProgressView(i18n.t(.search) + "...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Header (title only) for Playlists page to match Watch History spacing
                        if !showHeader {
                            HStack {
                                Text(i18n.t(.playlists))
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.primary)
                                Spacer()
                                // Auto Import button is fixed as floating overlay, so header contains only title
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 12)
                        }
                        // Local user playlists grid: show only on the sidebar playlists page (no header)
                        if !showHeader && !youtubeAPI.userPlaylists.isEmpty {
                            // Widen playlist cards a bit for better readability
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

                        // Searched playlists: only show in the dedicated search sheet (when showHeader == true)
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
                                // Empty state after a non-empty query
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
            // Floating Auto Import button when header hidden (matches Watch History style)
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
                    handleCSVDrop(providers: providers)
                }
                .padding(.top, 10)
                .padding(.trailing, 12)
            }
        }
    .background(Color(NSColor.controlBackgroundColor))
        // Allow dropping CSV anywhere in the page to import (only on playlists panel)
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            // Disable drop when used as the search sheet
            guard !showHeader else { return false }
            return handleCSVDrop(providers: providers)
        }
        .sheet(isPresented: $showingImportPanel) {
            PlaylistCSVImportView(youtubeAPI: youtubeAPI, isPresented: $showingImportPanel)
        }
        // When user starts playback from the search results, close the search panel immediately
        .onReceive(NotificationCenter.default.publisher(for: .openPlaylistModeOverlay)) { _ in
            if showHeader { dismiss() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openPlaylistMode)) { _ in
            if showHeader { dismiss() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .startAudioPlaylist)) { _ in
            if showHeader { dismiss() }
        }
    }
}

// MARK: - CSV Drop Handling
extension PlaylistSearchView {
    private func handleCSVDrop(providers: [NSItemProvider]) -> Bool {
    // Only enable CSV import via drop on the playlists panel, not in the search sheet
    if showHeader { return false }
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, error in
            guard let url = url else { return }
            if url.pathExtension.lowercased() == "csv" {
                if let content = try? String(contentsOf: url, encoding: .utf8) {
                    // Dayanıklı çözümleme: her satırdaki tüm alanları tarayıp URL/ID çıkar
                    let tokens = robustCSVTokenize(content: content)
                    // Dosya adını playlist adı olarak kullanmak için özel token ekle
                    let filename = url.deletingPathExtension().lastPathComponent
                    let payload = ["__CSV_FILENAME__=\(filename)"] + tokens
                    DispatchQueue.main.async { youtubeAPI.importPlaylists(from: payload) }
                }
            }
        }
        return true
    }

    /// CSV içeriğinden playlist/video token'larını güvenli şekilde çıkarır.
    /// Algoritma: her satırı ; , veya tab’a göre böl, tüm alanlarda şu kalıpları ara:
    ///  - YouTube URL ("youtu" içeriyorsa alanı ham olarak ekle)
    ///  - Playlist ID (PL/LL/UU/OL/FL/WL/RD ile başlıyorsa)
    ///  - Video ID (11 karakter, [A-Za-z0-9_-]{11})
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
                // YouTube URL alanını doğrudan ekleyelim (ileride extract* fonksiyonları temizler)
                if lower.contains("youtu.be") || lower.contains("youtube.com") {
                    out.insert(token)
                    continue
                }
                // Playlist ID kalıbı
                if token.count >= 2 {
                    let prefixes = ["PL","LL","UU","OL","FL","RD"]
                    if prefixes.contains(where: { token.hasPrefix($0) }) || token == "WL" {
                        out.insert(token)
                        continue
                    }
                }
                // 11 karakterlik video ID
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
