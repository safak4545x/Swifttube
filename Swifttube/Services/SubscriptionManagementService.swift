
/*
 File Overview (EN)
 Purpose: Manage subscription actions (subscribe/unsubscribe), persist the list, and refresh related feeds.
 Key Responsibilities:
 - Add/remove channels from the user’s subscriptions with sorting
 - Save/load subscriptions from UserDefaults and print diagnostics
 - Trigger subscription feed refresh and subscriber count updates
 Used By: SubscriptionsView actions and channel context menus.

 Dosya Özeti (TR)
 Amacı: Abonelik işlemlerini (abone ol/çıkar) yönetmek, listeyi kalıcı kılmak ve ilgili akışları yenilemek.
 Ana Sorumluluklar:
 - Kullanıcının abonelik listesine kanalları eklemek/çıkarmak ve sıralamak
 - Abonelikleri UserDefaults’a kaydetmek/okumak ve tanılama mesajları yazmak
 - Abonelik akışını ve abone sayısı güncellemelerini tetiklemek
 Nerede Kullanılır: SubscriptionsView eylemleri ve kanal bağlam menüleri.
*/

import Foundation

extension YouTubeAPIService {
    
    // Kanala abone ol
    func subscribeToChannel(_ channel: YouTubeChannel) {
        print("🔔 Attempting to subscribe to channel: \(channel.title) (ID: \(channel.id))")
        
        // Zaten abone olup olmadığını kontrol et
        if !userSubscriptionsFromURL.contains(where: { $0.id == channel.id }) {
            print("✅ Channel not in subscription list, adding...")
            // Abone olurken artık subscriberCount'u sıfırlamıyoruz; mevcut değer korunur (çoğunlukla 0, resmi API güncelleyecek).
            let sanitized = YouTubeChannel(
                id: channel.id,
                title: channel.title,
                description: channel.description,
                thumbnailURL: channel.thumbnailURL,
                bannerURL: channel.bannerURL,
                subscriberCount: channel.subscriberCount,
                videoCount: channel.videoCount
            )
            userSubscriptionsFromURL.append(sanitized)
            userSubscriptionsFromURL.sort { $0.title < $1.title }
            
            // Abonelik listesini kalıcı olarak kaydet
            saveSubscriptionsToUserDefaults()
            
            print("✅ Subscribed to channel: \(channel.title)")
            print("📊 Total subscriptions: \(userSubscriptionsFromURL.count)")
            
            // UI state'ini güncellemeyi zorla
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
            
            // Abonelik videolarını güncelle
            if !userSubscriptionsFromURL.isEmpty {
                fetchSubscriptionVideos()
                refreshSubscriberCounts(for: [channel.id])
            }
        } else {
            print("⚠️ Already subscribed to channel: \(channel.title)")
        }
    }
    
    // Kanaldan aboneliği kaldır
    func unsubscribeFromChannel(_ channel: YouTubeChannel) {
        userSubscriptionsFromURL.removeAll { $0.id == channel.id }
        
        // Abonelik listesini kalıcı olarak kaydet
        saveSubscriptionsToUserDefaults()
        
        print("❌ Unsubscribed from channel: \(channel.title)")
        print("📊 Total subscriptions: \(userSubscriptionsFromURL.count)")
        
        // UI state'ini güncellemeyi zorla
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
        
        // Abonelik videolarını güncelle
        if !userSubscriptionsFromURL.isEmpty {
            fetchSubscriptionVideos()
        } else {
            subscriptionVideos = []
        }
    }
    
    // Kanala abone olup olmadığını kontrol et
    func isSubscribedToChannel(_ channelId: String) -> Bool {
        return userSubscriptionsFromURL.contains { $0.id == channelId }
    }
    
    // Abonelikleri UserDefaults'a kaydet
    private func saveSubscriptionsToUserDefaults() {
        print("💾 Attempting to save \(userSubscriptionsFromURL.count) subscriptions to UserDefaults")
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(userSubscriptionsFromURL) {
            UserDefaults.standard.set(encoded, forKey: "userSubscriptions")
            UserDefaults.standard.synchronize() // Zorla senkronize et
            print("✅ Subscriptions saved successfully to UserDefaults")
            
            // Doğrulama için hemen yeniden oku
            if let verifyData = UserDefaults.standard.data(forKey: "userSubscriptions"),
               let verifyDecoded = try? JSONDecoder().decode([YouTubeChannel].self, from: verifyData) {
                print("✅ Verification: \(verifyDecoded.count) subscriptions found in UserDefaults")
            } else {
                print("❌ Verification failed: Could not read back from UserDefaults")
            }
        } else {
            print("❌ Failed to encode subscriptions for UserDefaults")
        }
    }
    
    // Abonelikleri UserDefaults'tan yükle
    func loadSubscriptionsFromUserDefaults() {
        print("📂 Attempting to load subscriptions from UserDefaults...")
        if let data = UserDefaults.standard.data(forKey: "userSubscriptions") {
            print("📂 Found subscription data in UserDefaults, size: \(data.count) bytes")
            let decoder = JSONDecoder()
            if let decodedSubscriptions = try? decoder.decode([YouTubeChannel].self, from: data) {
                // Persist edilen subscriberCount değerlerini artık sıfırlamıyoruz; olduğu gibi bırak.
                userSubscriptionsFromURL = decodedSubscriptions.sorted { $0.title < $1.title }
                print("✅ Successfully loaded \(userSubscriptionsFromURL.count) subscriptions from UserDefaults")
                
                // Yüklenen kanalları listele
                for (index, channel) in userSubscriptionsFromURL.enumerated() {
                    print("  \(index + 1). \(channel.title) (ID: \(channel.id))")
                }
                // Kick off official subscriber refresh in background
                refreshSubscriberCounts(for: userSubscriptionsFromURL.map { $0.id })
            } else {
                print("❌ Failed to decode subscription data from UserDefaults")
            }
        } else {
            print("📂 No subscription data found in UserDefaults")
        }
    }
    
    // Kanal ID'si ile yerel (scrape) tabanlı minimal kanal objesi oluşturup abone ol
    func subscribeToChannelById(_ channelId: String, channelTitle: String = "", channelThumbnail: String = "") {
        // LocalChannelAdapter kullanarak kanal bilgilerini zenginleştirmeyi dene (asenkron)
        Task {
            if let detailed = await LocalChannelAdapter.fetchChannelDetails(channelId: channelId) {
                subscribeToChannel(detailed)
            } else {
                // Fallback minimal bilgi
                let channel = YouTubeChannel(
                    id: channelId,
                    title: channelTitle.isEmpty ? "Unknown Channel" : channelTitle,
                    description: "",
                    thumbnailURL: channelThumbnail,
                    bannerURL: nil,
                    subscriberCount: 0,
                    videoCount: 0
                )
                subscribeToChannel(channel)
            }
        }
    }
}
