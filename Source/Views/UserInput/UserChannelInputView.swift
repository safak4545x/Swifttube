/*
 Overview / Genel Bakış
 EN: Input form to paste a channel URL or import a CSV of channels; adds channels to subscriptions.
 TR: Kanal URL’si yapıştırma veya CSV ile kanal içe aktarma formu; kanalları aboneliklere ekler.
*/

// EN: SwiftUI for UI; UTType for drag & drop. TR: UI için SwiftUI; sürükle-bırak için UTType.
import SwiftUI
import UniformTypeIdentifiers

// EN: Lets users add a channel via URL or CSV list. TR: Kullanıcıların URL veya CSV listesiyle kanal eklemesini sağlar.
struct UserChannelInputView: View {
    @EnvironmentObject var i18n: Localizer
    // EN: Text binding for manual URL entry. TR: Manuel URL girişi için metin binding'i.
    @Binding var userChannelURL: String
    // EN: API service to process channels. TR: Kanalları işleyen API servisi.
    @ObservedObject var youtubeAPI: YouTubeAPIService
    // EN: Callbacks for submit/cancel actions. TR: Gönder/iptal eylemleri için geri çağrılar.
    let onSubmit: (String) -> Void
    let onCancel: () -> Void
    // EN: Focus and drag/drop states. TR: Odak ve sürükle/bırak durumları.
    @FocusState private var isTextFieldFocused: Bool
    @State private var isDragOver = false
    @State private var isProcessingCSV = false
    @State private var csvProcessMessage = ""
    @State private var csvFileDropped = false
    @State private var csvFileName = ""
    @State private var csvChannelCount = 0
    @State private var processProgress: Double = 0.0
    // EN: Collected channel URLs from CSV. TR: CSV'den toplanan kanal URL'leri.
    @State private var csvChannelURLs: [String] = []
    
    var body: some View {
        VStack(spacing: 20) {
            // Başlık
            // EN: Dialog title. TR: Diyalog başlığı.
            Text(i18n.t(.addChannel))
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.top, 20)
            
            VStack(spacing: 16) {
                // EN: CSV drop zone for bulk channel import. TR: Toplu kanal içe aktarma için CSV bırakma alanı.
                VStack(spacing: 12) {
                    Text(i18n.t(.subscriptions))
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
                                        // EN: Linear progress while processing. TR: İşleme sırasında doğrusal ilerleme.
                                        ProgressView(value: processProgress)
                                            .progressViewStyle(LinearProgressViewStyle())
                                            .frame(width: 200)
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
                                        Text("\(csvChannelCount) \(i18n.t(.subscriptions))")
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
                                        Text("subscriptions.csv")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        
                                        // Debug bilgisi
                                        if !csvProcessMessage.isEmpty {
                                            // EN: Debug status (optional) for drop feedback. TR: Bırakma geri bildirimi için (opsiyonel) hata durumu.
                                            Text("Status: \(csvProcessMessage)")
                                                .font(.caption)
                                                .foregroundColor(.red)
                                        }
                                    }
                                }
                            }
                        )
                        .onDrop(of: [UTType.fileURL], isTargeted: $isDragOver) { providers in
                            print("🔍 CSV dosyası drop edildi, provider sayısı: \(providers.count)")
                            return handleCSVDrop(providers: providers)
                        }
                    
                    if !isProcessingCSV && !csvFileDropped {
                        Text(i18n.t(.subscriptionsCSVHint))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                
                // Ayırıcı
                HStack {
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(.gray.opacity(0.3))
                    Text(i18n.t(.orWord))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(.gray.opacity(0.3))
                }
                
                // EN: Manual single-channel URL entry. TR: Manuel tek kanal URL girişi.
                VStack(alignment: .leading, spacing: 8) {
                    Text(i18n.t(.enterChannelURL))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    TextField(i18n.t(.channelURLPlaceholder), text: $userChannelURL)
                        .textFieldStyle(.roundedBorder)
                        .focused($isTextFieldFocused)
                        .onSubmit {
                            if !userChannelURL.isEmpty {
                                onSubmit(userChannelURL)
                            }
                        }
                    
                    // EN: Supported URL formats hint. TR: Desteklenen URL biçimleri ipucu.
                    VStack(alignment: .leading, spacing: 4) {
                        Text(i18n.t(.supportedFormats))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(i18n.t(.supportedFormatHandle))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(i18n.t(.supportedFormatC))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(i18n.t(.supportedFormatChannelId))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(i18n.t(.supportedFormatUser))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, 20)
            
            Spacer()
            
            // EN: Action buttons for cancel/add. TR: İptal/ekle eylem butonları.
            HStack(spacing: 12) {
                Button(i18n.t(.cancel)) {
                    onCancel()
                }
                .buttonStyle(.bordered)
                
                if csvFileDropped {
                    Button(i18n.t(.addChannel)) {
                        processCSVFile()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isProcessingCSV)
                } else {
                    Button(i18n.t(.addChannel)) {
                        if !userChannelURL.isEmpty {
                            onSubmit(userChannelURL)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(userChannelURL.isEmpty)
                }
            }
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
        .onAppear {
            // EN: Auto-focus the input for quick paste. TR: Hızlı yapıştırma için otomatik odakla.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
            }
        }
    }
    
    func handleCSVDrop(providers: [NSItemProvider]) -> Bool {
        print("🔍 handleCSVDrop çağrıldı, provider sayısı: \(providers.count)")
        guard let provider = providers.first else { 
            print("❌ Provider bulunamadı")
            return false 
        }
        
        print("🔍 Provider type identifiers: \(provider.registeredTypeIdentifiers)")
        
        // EN: Try UTType.fileURL first. TR: Önce UTType.fileURL ile dene.
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (urlData, error) in
                DispatchQueue.main.async {
                    if let error = error {
                        print("❌ loadItem hatası: \(error.localizedDescription)")
                        self.csvProcessMessage = "\(i18n.t(.fileLoadErrorPrefix)): \(error.localizedDescription)"
                        return
                    }
                    
                    if let url = urlData as? URL {
                        print("✅ CSV dosyası URL'si alındı: \(url.lastPathComponent)")
                        self.csvFileName = url.lastPathComponent
                        self.analyzeCSVFile(url: url)
                    } else if let urlData = urlData as? Data, let urlString = String(data: urlData, encoding: .utf8), let url = URL(string: urlString) {
                        print("✅ CSV dosyası URL'si data'dan alındı: \(url.lastPathComponent)")
                        self.csvFileName = url.lastPathComponent
                        self.analyzeCSVFile(url: url)
                    } else {
                        print("❌ URL dönüştürme hatası")
            self.csvProcessMessage = i18n.t(.fileFormatNotSupported)
                    }
                }
            }
        } else {
            print("❌ FileURL type identifier desteklenmiyor")
            DispatchQueue.main.async {
        self.csvProcessMessage = i18n.t(.unsupportedFileType)
            }
            return false
        }
        
        return true
    }
    
    func analyzeCSVFile(url: URL) {
    print("🔍 CSV dosyası analiz başlıyor: \(url.lastPathComponent)")
    csvProcessMessage = i18n.t(.processingCSV)
        
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            print("✅ CSV dosyası okundu, karakter sayısı: \(content.count)")
            
            let lines = content.components(separatedBy: .newlines)
            print("📄 CSV satır sayısı: \(lines.count)")
            
            guard lines.count > 1 else { 
                print("❌ Geçersiz CSV formatı - yeterli satır yok")
                csvProcessMessage = i18n.t(.invalidCSV)
                return 
            }
            
            // İlk satırdan kolon başlıklarını al
            let headers = lines[0].components(separatedBy: ",")
            print("📝 CSV başlıkları: \(headers)")
            var urlColumnIndex = -1
            
            // URL kolonunu bul (Türkçe ve İngilizce başlıkları destekle)
            for (index, header) in headers.enumerated() {
                let cleanHeader = header.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if cleanHeader.contains("channel url") || 
                   cleanHeader.contains("kanal url") ||
                   cleanHeader.contains("url") {
                    urlColumnIndex = index
                    print("✅ URL kolonu bulundu: index \(index), başlık: '\(header)'")
                    break
                }
            }
            
            // URL kolonu bulunamazsa ikinci kolonu dene
            if urlColumnIndex == -1 && headers.count >= 2 {
                urlColumnIndex = 1
                print("⚠️ URL kolonu bulunamadı, ikinci kolonu deneyeceğiz: index 1")
            }
            
            guard urlColumnIndex != -1 else { 
                print("❌ CSV'de URL kolonu bulunamadı")
                csvProcessMessage = i18n.t(.csvURLColumnNotFound)
                return 
            }
            
            // URL'leri çıkar
            var channelURLs: [String] = []
            
            for (lineIndex, line) in lines.dropFirst().enumerated() {
                if line.isEmpty { continue }
                
                let columns = line.components(separatedBy: ",")
                if columns.count > urlColumnIndex {
                    let url = columns[urlColumnIndex].trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\"", with: "")
                    if !url.isEmpty && url.contains("youtube.com") {
                        channelURLs.append(url)
                        if lineIndex < 3 { // İlk 3 URL'yi log'la
                            print("✅ Geçerli URL bulundu: \(url)")
                        }
                    } else if !url.isEmpty {
                        if lineIndex < 3 { // İlk 3 geçersiz URL'yi log'la
                            print("⚠️ Geçersiz URL atlandı: \(url)")
                        }
                    }
                }
            }
            
            print("✅ CSV'den \(channelURLs.count) kanal URL'i bulundu")
            
            // Sonuçları kaydet
            csvChannelURLs = channelURLs
            csvChannelCount = channelURLs.count
            csvFileDropped = true
            csvProcessMessage = ""
            print("✅ CSV analizi tamamlandı: csvFileDropped = \(csvFileDropped)")
            
        } catch {
            print("❌ CSV dosyası okunurken hata: \(error)")
            csvProcessMessage = "\(i18n.t(.fileLoadErrorPrefix)): \(error.localizedDescription)"
        }
    }
    
    func processCSVFile() {
        guard !csvChannelURLs.isEmpty else { 
            print("❌ processCSVFile: csvChannelURLs boş")
            return 
        }
        
        print("🔄 processCSVFile başlıyor: \(csvChannelURLs.count) URL işlenecek")
        print("🔗 İlk 3 URL: \(Array(csvChannelURLs.prefix(3)))")
        
        isProcessingCSV = true
        processProgress = 0.0
        csvProcessMessage = "Abonelikler yükleniyor..."
        
        // Progress bar animasyonu
        withAnimation(.linear(duration: 3.0)) {
            processProgress = 1.0
        }
        
        // Kanal URL'lerini işle
        print("🚀 youtubeAPI.processBatchChannelURLs çağrılıyor")
        youtubeAPI.processBatchChannelURLs(csvChannelURLs)
        
        // 3 saniye sonra modal'ı kapat
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            print("✅ processCSVFile tamamlandı, modal kapanıyor")
            onCancel()
        }
    }
}
