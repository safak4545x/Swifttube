
/*
 File Overview (EN)
 Purpose: Utilities for constructing YouTube watch/thumbnail URLs and time parameter handling for deep links.
 Key Responsibilities:
 - Build watch URLs with start time; generate high/medium/low thumbnail URLs
 - Provide helpers to extract/format time parameters (t=)
 - Keep URL building consistent across views
 Used By: Video cards, detail views, and mini/overlay handoffs.

 Dosya Özeti (TR)
 Amacı: YouTube izleme/küçük görsel URL’lerini ve derin bağlantı zaman parametrelerini oluşturmak için yardımcılar.
 Ana Sorumluluklar:
 - Başlangıç zamanı içeren izleme URL’leri; yüksek/orta/düşük küçük görsel URL’leri üretmek
 - Zaman parametrelerini (t=) çıkarmak/formatlamak için yardımcılar sağlamak
 - Görünümler arasında URL oluşturmayı tutarlı tutmak
 Nerede Kullanılır: Video kartları, detay görünümleri ve mini/overlay geçişleri.
*/

import SwiftUI

// Video URL Service for YouTube
class VideoURLService: ObservableObject {
    @Published var videoURL: String?
    @Published var isLoading = false
    @Published var error: String?

    func getVideoURL(for videoId: String) {
        isLoading = true
        error = nil

        // YouTube embed URL (privacy-enhanced) kullan
        let embedURL =
            "https://www.youtube-nocookie.com/embed/\(videoId)?autoplay=1&controls=0&modestbranding=1&rel=0&showinfo=0&iv_load_policy=3&disablekb=1&fs=0&cc_load_policy=0&color=white&playsinline=1"

        DispatchQueue.main.async {
            self.videoURL = embedURL
            self.isLoading = false
        }
    }
}
