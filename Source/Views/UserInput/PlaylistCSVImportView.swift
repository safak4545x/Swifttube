/*
 File Overview (EN)
 Purpose: CSV import UI for local playlists; parse, validate, and create or update playlists from user-provided files.
 Key Responsibilities:
 - Let users pick CSV files and parse rows with robust error handling
 - Create new playlists or append items while avoiding duplicates
 - Show progress and result summaries to the user
 Used By: Playlist management workflows under Settings or context menus.

 Dosya Özeti (TR)
 Amacı: Yerel oynatma listeleri için CSV içe aktarma arayüzü; kullanıcının verdiği dosyalardan ayrıştırıp liste oluşturmak/güncellemek.
 Ana Sorumluluklar:
 - Kullanıcıların CSV dosyası seçmesine izin vermek ve satırları sağlam hata ele alımıyla ayrıştırmak
 - Yeni oynatma listeleri oluşturmak veya kopyaları önleyerek öğeler eklemek
 - Kullanıcıya ilerleme ve sonuç özetleri göstermek
 Nerede Kullanılır: Ayarlar veya bağlam menülerindeki oynatma listesi yönetimi akışlarında.
*/

import SwiftUI
import UniformTypeIdentifiers

struct PlaylistCSVImportView: View {
    @EnvironmentObject var i18n: Localizer
    @ObservedObject var youtubeAPI: YouTubeAPIService
    @Binding var isPresented: Bool
    @State private var isDragOver = false
    @State private var isProcessingCSV = false
    @State private var csvProcessMessage = ""
    @State private var csvFileDropped = false
    @State private var csvFileName = ""
    @State private var csvPlaylistCount = 0
    @State private var playlistTokens: [String] = []

    var body: some View {
        VStack(spacing: 20) {
            Text(i18n.t(.playlists))
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.top, 20)

            VStack(spacing: 16) {
                VStack(spacing: 12) {
                    Text(i18n.t(.playlists))
                        .font(.headline)
                        .foregroundColor(.primary)

                    RoundedRectangle(cornerRadius: 12)
                        .fill(isDragOver ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isDragOver ? Color.blue : Color.gray.opacity(0.3), lineWidth: 2)
                                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: csvFileDropped ? [] : [5]))
                        )
                        .frame(height: 120)
                        .overlay(
                            VStack(spacing: 8) {
                                if isProcessingCSV {
                                    VStack(spacing: 8) {
                                        ProgressView()
                                        Text(csvProcessMessage)
                                            .font(.subheadline)
                                            .foregroundColor(.blue)
                                            .multilineTextAlignment(.center)
                                    }
                                } else if csvFileDropped {
                                    VStack(spacing: 8) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 30))
                                            .foregroundColor(.green)
                                        Text(csvFileName)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        Text("\(csvPlaylistCount) \(i18n.t(.playlists))")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                } else {
                                    VStack(spacing: 8) {
                                        Image(systemName: "doc.badge.plus")
                                            .font(.system(size: 30))
                                            .foregroundColor(isDragOver ? .blue : .secondary)
                                        Text(isDragOver ? i18n.t(.dropTheFile) : i18n.t(.dragCSVHere))
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        Text("playlists.csv")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        )
                        .onDrop(of: [UTType.fileURL], isTargeted: $isDragOver) { providers in
                            handleCSVDrop(providers: providers)
                        }

                    if !isProcessingCSV && !csvFileDropped {
                        Text(i18n.t(.playlistsCSVHint))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding(.horizontal, 20)

            Spacer()

            HStack(spacing: 12) {
                Button(i18n.t(.cancel)) { isPresented = false }
                    .buttonStyle(.bordered)
                Button(i18n.t(.ok)) {
                    var payload = playlistTokens
                    if !csvFileName.isEmpty {
                        let title = URL(fileURLWithPath: csvFileName).deletingPathExtension().lastPathComponent
                        payload.insert("__CSV_FILENAME__=\(title)", at: 0)
                    }
                    youtubeAPI.importPlaylists(from: payload)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(playlistTokens.isEmpty)
            }
            .padding(.bottom, 20)
        }
    .frame(width: 520, height: 380)
    .background(Color(NSColor.controlBackgroundColor))
    }

    private func handleCSVDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (urlData, error) in
                DispatchQueue.main.async {
                    if let url = urlData as? URL {
                        csvFileName = url.lastPathComponent
                        analyzeCSVFile(url: url)
                    } else if let data = urlData as? Data, let s = String(data: data, encoding: .utf8), let url = URL(string: s) {
                        csvFileName = url.lastPathComponent
                        analyzeCSVFile(url: url)
                    } else {
                        csvProcessMessage = i18n.t(.fileFormatNotSupported)
                    }
                }
            }
            return true
        }
        csvProcessMessage = i18n.t(.unsupportedFileType)
        return false
    }

    private func analyzeCSVFile(url: URL) {
        isProcessingCSV = true
        csvProcessMessage = i18n.t(.processingCSV)
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let tokens = robustCSVTokenize(content: content)
            playlistTokens = tokens
            csvPlaylistCount = tokens.count
            csvFileDropped = true
            csvProcessMessage = ""
        } catch {
            csvProcessMessage = "\(i18n.t(.fileLoadErrorPrefix)): \(error.localizedDescription)"
        }
        isProcessingCSV = false
    }
}

// MARK: - Robust CSV parsing shared helper
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
            // Prefer URL passthrough
            if lower.contains("youtu.be") || lower.contains("youtube.com") {
                out.insert(token)
                continue
            }
            // Playlist ID prefixes
            if token.count >= 2 {
                let prefixes = ["PL","LL","UU","OL","FL","RD"]
                if prefixes.contains(where: { token.hasPrefix($0) }) || token == "WL" {
                    out.insert(token)
                    continue
                }
            }
            // 11-char video id
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
