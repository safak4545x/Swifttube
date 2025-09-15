

/*
 File Overview (EN)
 Purpose: Process multiple channel URLs, resolve channel info, and populate the user’s subscription list in bulk.
 Key Responsibilities:
 - Extract channel IDs from URLs and fetch minimal channel info via local adapter
 - Persist subscriptions to UserDefaults with verification reads
 - Trigger subscription feed loading after batch completion
 Used By: Onboarding/import flows to quickly build a subscriptions sidebar.

 Dosya Özeti (TR)
 Amacı: Birden çok kanal URL’sini işleyip kanal bilgilerini alarak kullanıcının abonelik listesini toplu halde oluşturmak.
 Ana Sorumluluklar:
 - URL’lerden kanal ID’lerini çıkarıp yerel adaptörle temel kanal bilgisini almak
 - Abonelikleri UserDefaults’a kalıcı olarak yazmak ve doğrulama okumaları yapmak
 - Toplu işlemin sonunda abonelik akışını tetiklemek
 Nerede Kullanılır: İlk kurulum/içe aktarma akışlarında abonelik kenar çubuğunu hızlıca oluşturmak.
*/

import Foundation

extension YouTubeAPIService {
    
    func processBatchChannelURLs(_ urls: [String]) {
        isLoadingUserData = true
        userChannelError = nil
        var loadedChannels: [YouTubeChannel] = []
        var processedCount = 0
        let totalCount = min(urls.count, 20) // Maksimum 20 kanal işle
        
        print("🔄 \(totalCount) kanal işlenecek...")
        
        // İlk URL'yi kullanıcının ana kanalı olarak ayarla (ama subscriptions çekme)
        if let firstURL = urls.first {
            if let channelId = extractChannelId(from: firstURL) {
                fetchUserChannelInfoOnly(channelId: channelId)
            }
        }
        
        // Tüm URL'lerden kanal bilgilerini al (ana kanal dahil)
        for url in urls.prefix(totalCount) {
            guard let channelId = extractChannelId(from: url) else {
                processedCount += 1
                print("❌ URL parse edilemedi: \(url)")
                if processedCount == totalCount {
                    // Tüm abonelikleri userSubscriptionsFromURL'e ekle
                    self.userSubscriptionsFromURL = loadedChannels.sorted { $0.title < $1.title }
                    self.isLoadingUserData = false
                    print("✅ \(loadedChannels.count) kanal yüklendi")
                    
                    // ÖNEMLI: Otomatik yüklenen kanalları UserDefaults'a kaydet
                    self.saveSubscriptionsToUserDefaults()
                }
                continue
            }
            
            fetchChannelInfoForBatch(channelId: channelId) { channel in
                DispatchQueue.main.async {
                    if let channel = channel {
                        loadedChannels.append(channel)
                        print("✅ Kanal yüklendi: \(channel.title)")
                    }
                    processedCount += 1
                    
                    if processedCount == totalCount {
                        // Tüm abonelikleri userSubscriptionsFromURL'e ekle
                        self.userSubscriptionsFromURL = loadedChannels.sorted { $0.title < $1.title }
                        self.isLoadingUserData = false
                        print("🎉 Toplam \(loadedChannels.count) kanal sidebar'a eklendi!")
                        
                        // ÖNEMLI: Otomatik yüklenen kanalları UserDefaults'a kaydet
                        self.saveSubscriptionsToUserDefaults()
                        
                        // Abone videolarını da yükle
                        self.fetchSubscriptionVideos()
                    }
                }
            }
        }
    }
    
    func fetchChannelInfoForBatch(channelId: String, completion: @escaping (YouTubeChannel?) -> Void) {
        Task {
            let ch = await self.quickChannelInfo(channelId: channelId)
            completion(ch)
        }
    }
    
    // Abonelikleri UserDefaults'a kaydet (BatchChannelService için)
    private func saveSubscriptionsToUserDefaults() {
        print("💾 BatchChannelService: Attempting to save \(userSubscriptionsFromURL.count) subscriptions to UserDefaults")
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(userSubscriptionsFromURL) {
            UserDefaults.standard.set(encoded, forKey: "userSubscriptions")
            UserDefaults.standard.synchronize() // Zorla senkronize et
            print("✅ BatchChannelService: Subscriptions saved successfully to UserDefaults")
            
            // Doğrulama için hemen yeniden oku
            if let verifyData = UserDefaults.standard.data(forKey: "userSubscriptions"),
               let verifyDecoded = try? JSONDecoder().decode([YouTubeChannel].self, from: verifyData) {
                print("✅ BatchChannelService: Verification: \(verifyDecoded.count) subscriptions found in UserDefaults")
            } else {
                print("❌ BatchChannelService: Verification failed: Could not read back from UserDefaults")
            }
        } else {
            print("❌ BatchChannelService: Failed to encode subscriptions for UserDefaults")
        }
    }
}
