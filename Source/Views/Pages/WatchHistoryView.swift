/*
 Overview / Genel Bakış
 EN: Watch History page listing previously watched videos with actions.
 TR: İzleme Geçmişi sayfası; geçmiş videoları eylemlerle listeler.
*/

import SwiftUI
import UniformTypeIdentifiers

struct WatchHistoryView: View {
    @EnvironmentObject var i18n: Localizer
    @ObservedObject var youtubeAPI: YouTubeAPIService
    @Binding var selectedChannel: YouTubeChannel?
    @Binding var showChannelSheet: Bool
    @Binding var selectedVideo: YouTubeVideo?
    @State private var isTargeted = false
    @State private var showingImportPanel = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(i18n.t(.watchHistoryTitle))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
            // EN: Auto Import button (drop HTML to parse history). TR: Otomatik içe aktar (HTML sürükle-bırak).
                    Button(action: {
                        showingImportPanel = true
                    }) {
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
                                        .stroke(isTargeted ? Color.green : Color.clear, lineWidth: 2)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .onDrop(of: ["public.file-url"], isTargeted: $isTargeted) { providers in
                        handleFileDrop(providers: providers)
                    }
                    
                    Button(action: {
                        youtubeAPI.clearWatchHistory()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 14))
                            Text(i18n.t(.clear))
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(16)
                    }
                    .buttonStyle(.plain)
                    .disabled(youtubeAPI.watchHistory.isEmpty)
                }
                .padding(.horizontal, 24)
                
                if youtubeAPI.watchHistory.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        
                        Text(i18n.t(.noVideosYet))
                            .font(.title3)
                            .foregroundColor(.secondary)
                        
                        Text(i18n.t(.videosWillAppearHere))
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 100)
                } else {
                    LazyVGrid(
                        columns: [
                            GridItem(
                                .adaptive(minimum: 320, maximum: 420), spacing: 32)
                        ], spacing: 32
                    ) {
                        ForEach(youtubeAPI.watchHistory) { video in
                            VideoCardView(
                                video: video,
                                selectedVideo: $selectedVideo,
                                selectedChannel: $selectedChannel,
                                showChannelSheet: $showChannelSheet,
                                youtubeAPI: youtubeAPI
                            )
                            .onTapGesture {
                                // EN: Re-add to history to bump it to top. TR: Geçmişte en üste taşımak için tekrar ekle.
                                youtubeAPI.addToWatchHistory(video)
                                selectedVideo = video
                            }
                            .contextMenu {
                                Button(i18n.t(.removeFromHistory)) {
                                    youtubeAPI.removeFromWatchHistory(video)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
            .padding(.vertical, 20)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .sheet(isPresented: $showingImportPanel) {
            HTMLImportView(
                youtubeAPI: youtubeAPI,
                isPresented: $showingImportPanel
            )
        }
        .onAppear {
            // Önce kayıtlı watch history'yi yükle
            youtubeAPI.loadWatchHistoryFromUserDefaults()
            
            // Mevcut videoları kanal profil fotoğrafları ile güncelle
            youtubeAPI.updateExistingWatchHistoryWithChannelThumbnails()
        }
    }
    
    // MARK: - File Drop Handling
    
    private func handleFileDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        
        _ = provider.loadObject(ofClass: URL.self) { url, error in
            guard let url = url else {
                print("❌ Dosya URL'si alınamadı: \(error?.localizedDescription ?? "Bilinmeyen hata")")
                return
            }
            
            // HTML dosyası kontrolü
            if url.pathExtension.lowercased() == "html" {
                youtubeAPI.importWatchHistoryFromHTML(url)
            } else {
                print("❌ Geçersiz dosya türü. Lütfen HTML dosyası seçin.")
            }
        }
        
        return true
    }
}

// MARK: - HTML Import View
struct HTMLImportView: View {
    @EnvironmentObject var i18n: Localizer
    @ObservedObject var youtubeAPI: YouTubeAPIService
    @Binding var isPresented: Bool
    @State private var isDragOver = false
    @State private var isProcessingHTML = false
    @State private var htmlProcessMessage = ""
    @State private var htmlFileDropped = false
    @State private var htmlFileName = ""
    @State private var htmlVideoCount = 0
    
    var body: some View {
        VStack(spacing: 20) {
            // Başlık
            Text(i18n.t(.importYouTubeHistory))
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.top, 20)
            
            VStack(spacing: 16) {
                // HTML Dosya Yükleme Alanı
                VStack(spacing: 12) {
                    Text(i18n.t(.watchHistoryHTMLFile))
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isDragOver ? Color.green.opacity(0.2) : Color.gray.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isDragOver ? Color.green : Color.gray.opacity(0.3), lineWidth: 2)
                                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: htmlFileDropped ? [] : [5]))
                        )
                        .frame(height: 120)
                        .overlay(
                            VStack(spacing: 8) {
                                if isProcessingHTML {
                                    VStack(spacing: 8) {
                                        ProgressView()
                                            .scaleEffect(1.2)
                                        Text(htmlProcessMessage)
                                            .font(.subheadline)
                                            .foregroundColor(.green)
                                            .multilineTextAlignment(.center)
                                    }
                                } else if htmlFileDropped {
                                    VStack(spacing: 8) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 30))
                                            .foregroundColor(.green)
                                        Text(htmlFileName)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        Text("\(htmlVideoCount) \(i18n.t(.videoCountSuffix)) • \(i18n.t(.successImported))")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                } else {
                                    VStack(spacing: 8) {
                                        Image(systemName: "doc.badge.plus")
                                            .font(.system(size: 30))
                                            .foregroundColor(isDragOver ? .green : .secondary)
                                        Text(isDragOver ? i18n.t(.dropTheFile) : i18n.t(.dragHTMLHere))
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        Text(i18n.t(.historyHtmlExample))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        )
                        .onDrop(of: [UTType.fileURL], isTargeted: $isDragOver) { providers in
                            return handleHTMLDrop(providers: providers)
                        }
                    
                    Text(i18n.t(.importHint))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 30)
            
            Spacer()
            
            // Alt butonlar
            HStack(spacing: 16) {
                Button(i18n.t(.cancel)) {
                    isPresented = false
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                
                if htmlFileDropped {
                    Button(i18n.t(.done)) {
                        isPresented = false
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(.bottom, 20)
        }
        .frame(width: 500, height: 400)
    }
    
    // MARK: - HTML Drop Handling
    
    private func handleHTMLDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        
        isProcessingHTML = true
    htmlProcessMessage = i18n.t(.processingHtml)
        
        _ = provider.loadObject(ofClass: URL.self) { url, error in
            DispatchQueue.main.async {
                guard let url = url else {
                    self.isProcessingHTML = false
                    self.htmlProcessMessage = "❌ \(i18n.t(.fileCouldNotBeRead))"
                    return
                }
                
                // HTML dosyası kontrolü
                if url.pathExtension.lowercased() == "html" {
                    self.htmlFileName = url.lastPathComponent
                    self.youtubeAPI.importWatchHistoryFromHTML(url)
                    
                    // Simülasyon için kısa gecikme
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.isProcessingHTML = false
                        self.htmlFileDropped = true
                        self.htmlVideoCount = self.youtubeAPI.watchHistory.count
                        self.htmlProcessMessage = "✅ \(i18n.t(.successImported))"
                    }
                } else {
                    self.isProcessingHTML = false
                    self.htmlProcessMessage = "❌ \(i18n.t(.invalidFileType))"
                }
            }
        }
        
        return true
    }
}
