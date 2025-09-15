/*
 File Overview (EN)
 Purpose: Handle user-channel URL processing, lightweight channel info loading, and persistence of user subscriptions.
 Key Responsibilities:
 - Extract channel IDs from various YouTube URL formats (limited local-only resolution)
 - Load minimal channel info via local adapter and update userChannelFromURL
 - Persist and reload subscriptions from UserDefaults; basic error messages for unsupported usernames
 Used By: User onboarding (paste channel URL) and sidebar subscriptions management.

 Dosya Özeti (TR)
 Amacı: Kullanıcı-kanal URL işleme, hafif kanal bilgisi yükleme ve kullanıcı aboneliklerinin kalıcılığını sağlamak.
 Ana Sorumluluklar:
 - Çeşitli YouTube URL biçimlerinden kanal ID’si çıkarma (yerel modda sınırlı çözümleme)
 - Yerel adaptörle temel kanal bilgisini yükleyip userChannelFromURL alanını güncellemek
 - Abonelikleri UserDefaults’a kaydedip yüklemek; desteklenmeyen kullanıcı adları için temel uyarılar vermek
 Nerede Kullanılır: Kullanıcı başlangıç akışı (kanal URL yapıştırma) ve kenar çubuğu abonelik yönetimi.
*/

import Foundation

extension YouTubeAPIService {
    
    func extractChannelId(from urlString: String) -> String? {
        // YouTube URL formatları:
        // https://www.youtube.com/channel/CHANNEL_ID
        // https://www.youtube.com/@username
        // https://www.youtube.com/c/customname
        // https://www.youtube.com/user/username
        
        guard let url = URL(string: urlString) else { return nil }
        
        let path = url.path
        
        // Direct channel ID
        if path.hasPrefix("/channel/") {
            return String(path.dropFirst("/channel/".count))
        }
        
    // Handle @ format or custom names (local: we'll attempt to treat them as channelId directly not supported)
    if path.hasPrefix("/@") || path.hasPrefix("/c/") || path.hasPrefix("/user/") { return nil }
        
        return nil
    }
    
    func resolveChannelIdFromUsername(_ username: String) { userChannelError = "Kullanıcı adı çözümleme local modda desteklenmiyor" }
    
    func fetchUserChannelInfoOnly(channelId: String) {
        // Local attempt via scraping adapter
        Task { @MainActor in
            if let info = await self.quickChannelInfo(channelId: channelId) {
                self.userChannelFromURL = info
                print("✅ Local kanal bilgisi alındı: \(info.title)")
            } else {
                print("⚠️ Local kanal bilgisi bulunamadı")
            }
        }
    }
    
    func fetchUserChannelInfo(channelId: String) {
        isLoadingUserData = true
        userChannelError = nil
        Task { @MainActor in
            if let info = await self.quickChannelInfo(channelId: channelId) {
                self.userChannelFromURL = info
                self.fetchChannelSubscriptions(channelId: info.id)
            } else {
                self.userChannelError = "Kanal bulunamadı (local)"
            }
            self.isLoadingUserData = false
        }
    }
    
    func fetchChannelSubscriptions(channelId: String) { self.userSubscriptionsFromURL = [] }
    
    func fetchFeaturedChannels(channelIds: [String]) { self.userSubscriptionsFromURL = [] }
    
    func processUserChannelURL(_ urlString: String) {
        // URL'yi temizle ve normalize et
        var cleanURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // https:// yoksa ekle
        if !cleanURL.hasPrefix("http") {
            cleanURL = "https://" + cleanURL
        }
        
        // youtube.com yoksa ekle
        if !cleanURL.contains("youtube.com") {
            if cleanURL.hasPrefix("https://") {
                cleanURL = "https://www.youtube.com/@" + cleanURL.dropFirst("https://".count)
            } else {
                cleanURL = "https://www.youtube.com/@" + cleanURL
            }
        }
        
        // Channel ID'yi çıkar
        if let channelId = extractChannelId(from: cleanURL) {
            fetchUserChannelInfo(channelId: channelId)
        } else {
            // @ formatında ise username'i çözümle
            if let url = URL(string: cleanURL) {
                let path = url.path
                if path.hasPrefix("/@") {
                    let username = String(path.dropFirst(2))
                    resolveChannelIdFromUsername(username)
                } else if path.hasPrefix("/c/") {
                    let customName = String(path.dropFirst(3))
                    resolveChannelIdFromUsername(customName)
                } else if path.hasPrefix("/user/") {
                    let username = String(path.dropFirst(6))
                    resolveChannelIdFromUsername(username)
                }
            }
        }
    }
    
    // Abonelikleri UserDefaults'a kaydet (UserService için)
    private func saveSubscriptionsToUserDefaults() {
        print("💾 UserService: Attempting to save \(userSubscriptionsFromURL.count) subscriptions to UserDefaults")
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(userSubscriptionsFromURL) {
            UserDefaults.standard.set(encoded, forKey: "userSubscriptions")
            UserDefaults.standard.synchronize() // Zorla senkronize et
            print("✅ UserService: Subscriptions saved successfully to UserDefaults")
            
            // Doğrulama için hemen yeniden oku
            if let verifyData = UserDefaults.standard.data(forKey: "userSubscriptions"),
               let verifyDecoded = try? JSONDecoder().decode([YouTubeChannel].self, from: verifyData) {
                print("✅ UserService: Verification: \(verifyDecoded.count) subscriptions found in UserDefaults")
            } else {
                print("❌ UserService: Verification failed: Could not read back from UserDefaults")
            }
        } else {
            print("❌ UserService: Failed to encode subscriptions for UserDefaults")
        }
    }
    
}
