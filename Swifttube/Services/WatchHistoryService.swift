
/*
 File Overview (EN)
 Purpose: Manage watch history – add/remove/clear entries, import from HTML, persist to UserDefaults, and enrich thumbnails.
 Key Responsibilities:
 - Normalize view/date fields and insert items with recency order and size limits
 - Save/load history to/from UserDefaults with simple diagnostics
 - Import takeout HTML and backfill channel avatars via quick channel info
 Used By: Watch History page and mini player resume features.

 Dosya Özeti (TR)
 Amacı: İzleme geçmişini yönetmek – ekleme/silme/temizleme, HTML’den içe aktarma, UserDefaults’a kaydetme ve avatar zenginleştirme.
 Ana Sorumluluklar:
 - Görüntülenme/tarih alanlarını normalize edip öğeleri son-izlenen sırasıyla ve limitlere göre eklemek
 - Geçmişi UserDefaults’a kaydedip/okumak ve basit tanılama çıktıları vermek
 - YouTube takeout HTML’inden import ve hızlı kanal bilgisi ile avatar tamamlama
 Nerede Kullanılır: İzleme Geçmişi sayfası ve mini oynatıcı devam etme özellikleri.
*/

import Foundation

extension YouTubeAPIService {
    
    func addToWatchHistory(_ video: YouTubeVideo) {
        DispatchQueue.main.async {
            // Görüntülenme ve tarih alanlarını merkezî yardımcılarla normalize et
            let normalized = self.normalizeVideoDisplayFields(video)
            // Aynı video zaten varsa önce çıkar
            self.watchHistory.removeAll { $0.id == normalized.id }
            
            // En başa ekle (en son izlenen) - önce geçici olarak ekle
            self.watchHistory.insert(normalized, at: 0)
            
            // Maksimum limit aş kontrolü
            if self.watchHistory.count > self.maxHistoryItems {
                self.watchHistory = Array(self.watchHistory.prefix(self.maxHistoryItems))
            }
            
            // ÖNEMLI: Watch history'yi UserDefaults'a kaydet
            self.saveWatchHistoryToUserDefaults()
            
            // Gerçek kanal profil fotoğrafını API'den çek
            self.fetchChannelThumbnails(for: [normalized], isWatchHistory: true)
            
            print("📺 Video geçmişe eklendi ve kanal profil fotoğrafı API'den çekiliyor: \(normalized.title)")
        }
    }
    
    /// Geçmişten video sil
    func removeFromWatchHistory(_ video: YouTubeVideo) {
        DispatchQueue.main.async {
            self.watchHistory.removeAll { $0.id == video.id }
            
            // ÖNEMLI: Watch history'yi UserDefaults'a kaydet
            self.saveWatchHistoryToUserDefaults()
            
            print("🗑️ Video geçmişten silindi: \(video.title)")
        }
    }
    
    /// Tüm geçmişi temizle
    @MainActor
    func clearWatchHistory() {
        DispatchQueue.main.async {
            self.watchHistory.removeAll()
            
            // ÖNEMLI: Watch history'yi UserDefaults'a kaydet (boş liste)
            self.saveWatchHistoryToUserDefaults()
            
            print("🧹 Tüm geçmiş temizlendi")
        }
    }
    
    /// Mevcut watch history videolarını kanal profil fotoğrafları ile güncelle
    func updateExistingWatchHistoryWithChannelThumbnails() {
        guard !watchHistory.isEmpty else { return }
        
        print("🔄 Watch History videolarını gerçek YouTube API'den güncelleniyor...")
        
        // Gerçek YouTube API'den kanal profil fotoğraflarını çek
        fetchChannelThumbnails(for: watchHistory, isWatchHistory: true)
    }
    
    /// HTML dosyasından geçmiş verileri import et
    func importWatchHistoryFromHTML(_ url: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let htmlContent = try String(contentsOf: url, encoding: .utf8)
                let importedVideos = self.parseWatchHistoryHTML(htmlContent)
                
                DispatchQueue.main.async {
                    // Mevcut geçmişe ekle (duplikasyonları önle)
                    var addedVideos: [YouTubeVideo] = []
                    var addedCount = 0
                    
                    for video in importedVideos {
                        let normalized = self.normalizeVideoDisplayFields(video)
                        if !self.watchHistory.contains(where: { $0.id == video.id }) {
                            // Önce video'yu olduğu gibi ekle
                            self.watchHistory.append(normalized)
                            addedVideos.append(normalized)
                            addedCount += 1
                        }
                    }
                    
                    // Limit kontrolü
                    if self.watchHistory.count > self.maxHistoryItems {
                        self.watchHistory = Array(self.watchHistory.prefix(self.maxHistoryItems))
                    }
                    
                    // ÖNEMLI: Import edilen watch history'yi UserDefaults'a kaydet
                    self.saveWatchHistoryToUserDefaults()
                    
                    print("📄 HTML'den \(addedCount) video geçmişe eklendi")
                    
                    // Eklenen videolar için gerçek kanal profil fotoğraflarını API'den çek
                    if !addedVideos.isEmpty {
                        self.fetchChannelThumbnails(for: addedVideos, isWatchHistory: true)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    print("❌ HTML dosyası okunamadı: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// Video'yu kanal bilgileri ile zenginleştir
    private func enhanceVideoWithChannelInfo(_ video: YouTubeVideo) -> YouTubeVideo {
        // Kanal profil fotoğrafı URL'i oluştur
        let channelThumbnailURL = generateChannelThumbnailURL(for: video.channelTitle)
        
        return YouTubeVideo(
            id: video.id,
            title: video.title,
            channelTitle: video.channelTitle,
            channelId: video.channelId,
            viewCount: video.viewCount,
            publishedAt: video.publishedAt,
            thumbnailURL: video.thumbnailURL,
            description: video.description,
            channelThumbnailURL: channelThumbnailURL,
            likeCount: video.likeCount,
            durationText: video.durationText,
            durationSeconds: video.durationSeconds
        )
    }
    
    /// Kanal adı için thumbnail URL oluştur
    private func generateChannelThumbnailURL(for channelName: String) -> String {
        // Kanal adı bilinmiyorsa varsayılan avatar
        if channelName == "Bilinmeyen Kanal" || channelName.isEmpty {
            return "https://ui-avatars.com/api/?name=?&size=48&background=333333&color=ffffff&format=png"
        }
        
        // Kanal adının ilk harfini al
        let firstLetter = String(channelName.prefix(1)).uppercased()
        
        // Kanal adının hash'ine göre renk belirle
        let colors = [
            "FF6B6B", "4ECDC4", "45B7D1", "96CEB4", "FECA57",
            "FF9FF3", "54A0FF", "5F27CD", "00D2D3", "FF9F43",
            "10AC84", "EE5A24", "0984E3", "6C5CE7", "FD79A8"
        ]
        
        let colorIndex = abs(channelName.hashValue) % colors.count
        let backgroundColor = colors[colorIndex]
        
        // UI-Avatars.com kullanarak daha güvenilir avatar oluştur
        let encodedName = firstLetter.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? firstLetter
        return "https://ui-avatars.com/api/?name=\(encodedName)&size=48&background=\(backgroundColor)&color=ffffff&format=png&bold=true"
    }
    
    /// HTML içeriğini parse et ve video listesi döndür
    private func parseWatchHistoryHTML(_ htmlContent: String) -> [YouTubeVideo] {
        var videos: [YouTubeVideo] = []
        
        // YouTube takeout HTML formatında video girişlerini bul
        // Her video girdisi genellikle şu formatta olur:
        // <div class="content-cell mdl-cell mdl-cell--6-col mdl-typography--body-1">
        //   <a href="https://www.youtube.com/watch?v=VIDEO_ID">VIDEO_TITLE</a><br>
        //   <a href="https://www.youtube.com/channel/CHANNEL_ID">CHANNEL_NAME</a><br>
        //   DATE
        // </div>
        
        // Video girişlerini bul (content-cell div'leri)
        let entryPattern = #"<div class="content-cell[^"]*"[^>]*>(.*?)</div>"#
        
        do {
            let entryRegex = try NSRegularExpression(pattern: entryPattern, options: [.dotMatchesLineSeparators])
            let entryMatches = entryRegex.matches(
                in: htmlContent,
                options: [],
                range: NSRange(location: 0, length: htmlContent.count)
            )
            
            for entryMatch in entryMatches {
                if let entryRange = Range(entryMatch.range(at: 1), in: htmlContent) {
                    let entryContent = String(htmlContent[entryRange])
                    
                    // Video bilgilerini çıkar
                    var videoId = ""
                    var videoTitle = ""
                    var channelName = "Bilinmeyen Kanal"
                    var watchDate = "Bilinmiyor"
                    
                    // Video ID ve başlığını bul
                    let videoPattern = #"<a href="https://www\.youtube\.com/watch\?v=([a-zA-Z0-9_-]+)"[^>]*>([^<]+)</a>"#
                    if let videoMatch = try NSRegularExpression(pattern: videoPattern).firstMatch(
                        in: entryContent,
                        range: NSRange(location: 0, length: entryContent.count)
                    ) {
                        if let idRange = Range(videoMatch.range(at: 1), in: entryContent),
                           let titleRange = Range(videoMatch.range(at: 2), in: entryContent) {
                            videoId = String(entryContent[idRange])
                            videoTitle = String(entryContent[titleRange])
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .replacingOccurrences(of: "&amp;", with: "&")
                                .replacingOccurrences(of: "&lt;", with: "<")
                                .replacingOccurrences(of: "&gt;", with: ">")
                                .replacingOccurrences(of: "&quot;", with: "\"")
                        }
                    }
                    
                    // Kanal adını bul
                    let channelPattern = #"<a href="https://www\.youtube\.com/channel/[^"]*"[^>]*>([^<]+)</a>"#
                    if let channelMatch = try NSRegularExpression(pattern: channelPattern).firstMatch(
                        in: entryContent,
                        range: NSRange(location: 0, length: entryContent.count)
                    ) {
                        if let channelRange = Range(channelMatch.range(at: 1), in: entryContent) {
                            channelName = String(entryContent[channelRange])
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .replacingOccurrences(of: "&amp;", with: "&")
                                .replacingOccurrences(of: "&lt;", with: "<")
                                .replacingOccurrences(of: "&gt;", with: ">")
                                .replacingOccurrences(of: "&quot;", with: "\"")
                        }
                    }
                    
                    // Alternatif kanal pattern'i (bazı durumlarda farklı format kullanılabilir)
                    if channelName == "Bilinmeyen Kanal" {
                        let altChannelPattern = #"<a href="https://www\.youtube\.com/c/[^"]*"[^>]*>([^<]+)</a>"#
                        if let channelMatch = try NSRegularExpression(pattern: altChannelPattern).firstMatch(
                            in: entryContent,
                            range: NSRange(location: 0, length: entryContent.count)
                        ) {
                            if let channelRange = Range(channelMatch.range(at: 1), in: entryContent) {
                                channelName = String(entryContent[channelRange])
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                    .replacingOccurrences(of: "&amp;", with: "&")
                                    .replacingOccurrences(of: "&lt;", with: "<")
                                    .replacingOccurrences(of: "&gt;", with: ">")
                                    .replacingOccurrences(of: "&quot;", with: "\"")
                            }
                        }
                    }
                    
                    // Tarih bilgisini bul
                    let datePattern = #"([A-Z][a-z]{2} \d{1,2}, \d{4})"#
                    if let dateMatch = try NSRegularExpression(pattern: datePattern).firstMatch(
                        in: entryContent,
                        range: NSRange(location: 0, length: entryContent.count)
                    ) {
                        if let dateRange = Range(dateMatch.range(at: 1), in: entryContent) {
                            watchDate = String(entryContent[dateRange])
                        }
                    }
                    
                    // Geçerli video bilgisi varsa listeye ekle
                    if !videoId.isEmpty && !videoTitle.isEmpty {
                        // Watch date'i merkezî normalize ile çöz (mutlak/relatif → ISO → display)
                        let (displayDate, iso) = self.normalizePublishedAt(watchDate)
                        let video = YouTubeVideo(
                            id: videoId,
                            title: videoTitle,
                            channelTitle: channelName,
                            channelId: "", // HTML'de kanal ID'si genellikle bulunmaz
                            viewCount: "",
                            publishedAt: displayDate,
                            publishedAtISO: iso,
                            thumbnailURL: youtubeThumbnailURL(videoId, quality: .mqdefault),
                            description: "",
                            channelThumbnailURL: generateChannelThumbnailURL(for: channelName),
                            likeCount: "0",
                            durationText: "",
                            durationSeconds: nil
                        )
                        videos.append(video)
                    }
                }
            }
        } catch {
            print("❌ HTML parsing error: \(error.localizedDescription)")
        }
        
        return videos
    }
    
    // MARK: - Watch History UserDefaults Functions
    
    /// Watch History'yi UserDefaults'a kaydet
    private func saveWatchHistoryToUserDefaults() {
        print("💾 WatchHistory: Attempting to save \(watchHistory.count) videos to UserDefaults")
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(watchHistory) {
            UserDefaults.standard.set(encoded, forKey: "watchHistory")
            UserDefaults.standard.synchronize() // Zorla senkronize et
            print("✅ WatchHistory: \(watchHistory.count) videos saved successfully to UserDefaults")
            
            // Doğrulama için hemen yeniden oku
            if let verifyData = UserDefaults.standard.data(forKey: "watchHistory"),
               let verifyDecoded = try? JSONDecoder().decode([YouTubeVideo].self, from: verifyData) {
                print("✅ WatchHistory: Verification: \(verifyDecoded.count) videos found in UserDefaults")
            } else {
                print("❌ WatchHistory: Verification failed: Could not read back from UserDefaults")
            }
        } else {
            print("❌ WatchHistory: Failed to encode videos for UserDefaults")
        }
    }
    
    /// Watch History'yi UserDefaults'tan yükle
    func loadWatchHistoryFromUserDefaults() {
        print("📂 WatchHistory: Attempting to load videos from UserDefaults...")
        if let data = UserDefaults.standard.data(forKey: "watchHistory") {
            print("📂 WatchHistory: Found video data in UserDefaults, size: \(data.count) bytes")
            let decoder = JSONDecoder()
            if let decodedVideos = try? decoder.decode([YouTubeVideo].self, from: data) {
                // Eski kayıtları da normalize et (görüntülenme + tarih)
                watchHistory = decodedVideos.map { self.normalizeVideoDisplayFields($0) }
                print("✅ WatchHistory: Successfully loaded \(watchHistory.count) videos from UserDefaults")
                
                // Yüklenen videoları listele (ilk 5 tanesini)
                for (index, video) in watchHistory.prefix(5).enumerated() {
                    print("  \(index + 1). \(video.title) - \(video.channelTitle)")
                }
                if watchHistory.count > 5 {
                    print("  ... ve \(watchHistory.count - 5) video daha")
                }
            } else {
                print("❌ WatchHistory: Failed to decode video data from UserDefaults")
            }
        } else {
            print("📂 WatchHistory: No video data found in UserDefaults")
        }
    }
}

// MARK: - Normalization Helpers
private extension YouTubeAPIService {
    /// Apply central view-count and publishedAt normalization to a video
    func normalizeVideoDisplayFields(_ v: YouTubeVideo) -> YouTubeVideo {
        let normalizedViews = self.normalizeViewCount(v.viewCount)
        let (normalizedPublished, iso) = self.normalizePublishedAt(v.publishedAt, iso: v.publishedAtISO)
        return YouTubeVideo(
            id: v.id,
            title: v.title,
            channelTitle: v.channelTitle,
            channelId: v.channelId,
            viewCount: normalizedViews,
            publishedAt: normalizedPublished,
            publishedAtISO: iso,
            thumbnailURL: v.thumbnailURL,
            description: v.description,
            channelThumbnailURL: v.channelThumbnailURL,
            likeCount: v.likeCount,
            durationText: v.durationText,
            durationSeconds: v.durationSeconds
        )
    }
}
