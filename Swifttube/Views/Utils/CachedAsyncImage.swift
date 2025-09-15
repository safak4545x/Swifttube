/*
 Overview / Genel Bakış
 EN: Async image with lightweight caching and a placeholder, tailored for thumbnails.
 TR: Küçük resimler için hafif önbellekli, yer tutuculu asenkron görsel bileşeni.
*/

import SwiftUI
import AppKit

struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder var content: (Image) -> Content
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var nsImage: NSImage? = nil
    // EN: Track last loaded URL to reset when URL changes. TR: URL değişince sıfırlamak için son yüklenen URL'yi takip et.
    @State private var loadedURLString: String? = nil

    var body: some View {
        Group {
            if let nsImage {
                content(Image(nsImage: nsImage).renderingMode(.original))
            } else {
                placeholder()
            }
        }
        // EN: React to URL changes even if an image is already present. TR: Görsel mevcut olsa bile URL değişimine tepki ver.
        .task(id: url) {
            // EN: If URL differs from last one, clear image and load again. TR: URL öncekiyle farklıysa görseli temizleyip yeniden yükle.
            let next = url?.absoluteString
            if next != loadedURLString {
                loadedURLString = next
                // EN: Clear current image to show placeholder while fetching. TR: Yeni yükleme sırasında yer tutucuyu göstermek için mevcut görseli temizle.
                await MainActor.run { self.nsImage = nil }
                await load()
            }
        }
    }

    private func load() async {
        guard let url else { return }
        if let cached = await GlobalCaches.images.get(urlString: url.absoluteString) {
            await MainActor.run { self.nsImage = cached }
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let img = await GlobalCaches.images.set(urlString: url.absoluteString, data: data) {
                await MainActor.run { self.nsImage = img }
            }
        } catch {
            // EN: Ignore fetch errors; placeholder remains. TR: Yükleme hatalarını yok say; yer tutucu görünür.
        }
    }
}
