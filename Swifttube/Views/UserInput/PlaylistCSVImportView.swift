/*
 Overview / Genel Bakış
 EN: CSV import UI for local playlists; parse tokens and import robustly with drag & drop.
 TR: Yerel çalma listeleri için CSV içe aktarma arayüzü; belirteçleri ayrıştırır ve sürükle-bırak ile içe aktarır.
*/

// EN: UI framework and UTType for file drops. TR: UI çerçevesi ve dosya bırakma için UTType.
import SwiftUI
import UniformTypeIdentifiers

// EN: Modal view to import playlists from a CSV file. TR: CSV dosyasından playlist içe aktaran modal görünüm.
struct PlaylistCSVImportView: View {
    // EN: Localization provider. TR: Yerelleştirme sağlayıcı.
    @EnvironmentObject var i18n: Localizer
    // EN: Service to import parsed tokens. TR: Ayrıştırılan belirteçleri içe aktaran servis.
    @ObservedObject var youtubeAPI: YouTubeAPIService
    // EN: Controls modal presentation. TR: Modal gösterimini kontrol eder.
    @Binding var isPresented: Bool
    // EN: Drag state for drop target. TR: Bırakma hedefi için sürükleme durumu.
    @State private var isDragOver = false
    // EN: Processing indicator and status text. TR: İşleme göstergesi ve durum metni.
    @State private var isProcessingCSV = false
    @State private var csvProcessMessage = ""
    // EN: Post-drop state and summary. TR: Bırakma sonrası durum ve özet.
    @State private var csvFileDropped = false
    @State private var csvFileName = ""
    @State private var csvPlaylistCount = 0
    // EN: Tokens extracted from CSV (URLs or IDs). TR: CSV'den çıkarılan belirteçler (URL veya ID).
    @State private var playlistTokens: [String] = []

    var body: some View {
        VStack(spacing: 20) {
            // EN: Modal title. TR: Modal başlığı.
            Text(i18n.t(.playlists))
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.top, 20)

            VStack(spacing: 16) {
                VStack(spacing: 12) {
                    Text(i18n.t(.playlists))
                        .font(.headline)
                        .foregroundColor(.primary)

                    // EN: Drop zone with visual feedback. TR: Görsel geri bildirimli bırakma alanı.
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
                                    // EN: Show progress and status while parsing. TR: Ayrıştırma sırasında ilerleme ve durum göster.
                                    VStack(spacing: 8) {
                                        ProgressView()
                                        Text(csvProcessMessage)
                                            .font(.subheadline)
                                            .foregroundColor(.blue)
                                            .multilineTextAlignment(.center)
                                    }
                                } else if csvFileDropped {
                                    // EN: Show file summary after successful drop. TR: Başarılı bırakma sonrası dosya özetini göster.
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
                                    // EN: Idle hint with example filename. TR: Örnek dosya adıyla bekleme ipucu.
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
                            // EN: Handle file URL drop and start analysis. TR: Dosya URL bırakmayı işle ve analizi başlat.
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
                    // EN: Prepend filename token (used as playlist name) and import. TR: Dosya adını (playlist adı) başa ekle ve içe aktar.
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

    // EN: Accept a dropped file URL and kick off CSV analysis. TR: Bırakılan dosya URL'sini kabul edip CSV analizini başlat.
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

    // EN: Read CSV, tokenize robustly, and update UI state. TR: CSV'yi oku, sağlam biçimde belirteçle ve UI durumunu güncelle.
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
/// EN: Extract tokens from CSV lines: YouTube URLs, playlist IDs (PL/LL/UU/OL/FL/WL/RD), and 11-char video IDs.
/// TR: CSV satırlarından belirteç çıkar: YouTube URL'leri, playlist ID'leri (PL/LL/UU/OL/FL/WL/RD) ve 11 karakterlik video ID'leri.
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
            // EN: Keep YouTube URLs as-is; normalization happens upstream. TR: YouTube URL'lerini olduğu gibi bırak; normalize üstte yapılır.
            if lower.contains("youtu.be") || lower.contains("youtube.com") {
                out.insert(token)
                continue
            }
            // EN: Detect playlist IDs by common prefixes. TR: Playlist ID'lerini yaygın öneklerle saptar.
            if token.count >= 2 {
                let prefixes = ["PL","LL","UU","OL","FL","RD"]
                if prefixes.contains(where: { token.hasPrefix($0) }) || token == "WL" {
                    out.insert(token)
                    continue
                }
            }
            // EN: 11-char video ID via regex. TR: Regex ile 11 karakterlik video ID.
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
