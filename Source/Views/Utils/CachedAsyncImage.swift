/*
 File Overview (EN)
 Purpose: Async image view with lightweight caching and placeholder handling tailored for video/channel thumbnails.
 Key Responsibilities:
 - Display remote images with placeholder and error tolerance
 - Integrate with app-level cache utilities where possible
 Used By: Thumbnails across cards, lists, and sidebars.

 Dosya Özeti (TR)
 Amacı: Video/kanal küçük resimleri için hafif önbellek ve yer tutuculu asenkron görsel bileşeni.
 Ana Sorumluluklar:
 - Uzaktaki görselleri yer tutucu ve hata toleransı ile göstermek
 - Mümkün olduğunda uygulama düzeyi cache yardımcılarıyla bütünleşmek
 Nerede Kullanılır: Kartlar, listeler ve yan menülerdeki thumbnail alanlarında.
*/

import SwiftUI
import AppKit

struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder var content: (Image) -> Content
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var nsImage: NSImage? = nil
    // Track last-loaded URL to react to URL changes
    @State private var loadedURLString: String? = nil

    var body: some View {
        Group {
            if let nsImage {
                content(Image(nsImage: nsImage).renderingMode(.original))
            } else {
                placeholder()
            }
        }
        // Always react to URL changes, even if we already have an image
        .task(id: url) {
            // If the incoming URL differs from what we previously loaded, reset and load
            let next = url?.absoluteString
            if next != loadedURLString {
                loadedURLString = next
                // Clear the current image so placeholder shows while fetching new one
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
            // ignore fetch errors
        }
    }
}
