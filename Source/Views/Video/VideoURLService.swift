
/*
 Overview / Genel Bakış
 EN: Small helper object that exposes a privacy-enhanced YouTube embed URL for a given video.
 TR: Verilen video için gizlilik artırılmış YouTube embed URL’si sağlayan küçük yardımcı nesne.
*/

// EN: Not UI-bound but kept with Views/Video for convenience. TR: UI bağlı değil; kolaylık için Views/Video altında tutulur.
import SwiftUI

// Video URL Service for YouTube
// EN: Publishes the current embed URL and loading state. TR: Geçerli embed URL’sini ve yükleme durumunu yayımlar.
class VideoURLService: ObservableObject {
    @Published var videoURL: String?
    @Published var isLoading = false
    @Published var error: String?

    func getVideoURL(for videoId: String) {
        isLoading = true
        error = nil

        // EN: Use the privacy-enhanced embed domain. TR: Gizlilik artırılmış embed alan adını kullan.
        let embedURL =
            "https://www.youtube-nocookie.com/embed/\(videoId)?autoplay=1&controls=0&modestbranding=1&rel=0&showinfo=0&iv_load_policy=3&disablekb=1&fs=0&cc_load_policy=0&color=white&playsinline=1"

        DispatchQueue.main.async {
            self.videoURL = embedURL
            self.isLoading = false
        }
    }
}
