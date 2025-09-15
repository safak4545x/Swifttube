/*
 File Overview (EN)
 Purpose: Manage default and custom cover images for local playlists, persisting copies under Application Support.
 Key Responsibilities:
 - Set/reset bundled cover names or store user-selected image files
 - Copy custom images into an internal app directory and clean up old copies
 - Update playlist models to reflect chosen cover source
 Used By: Settings/UI flows that change a playlist’s visual cover.

 Dosya Özeti (TR)
 Amacı: Yerel oynatma listeleri için varsayılan veya özel kapak görsellerini yönetmek; dosyaları Application Support altında kalıcı kılmak.
 Ana Sorumluluklar:
 - Paketle gelen kapak adlarını atamak/sıfırlamak veya kullanıcının seçtiği görsel dosyayı kullanmak
 - Özel görselleri uygulamanın iç dizinine kopyalamak ve eski kopyaları temizlemek
 - Seçilen kapak kaynağını modele yansıtmak
 Nerede Kullanılır: Oynatma listesi kapak değiştirme akışları (ayarlar/arayüz).
*/

import Foundation

// Playlist cover helpers extracted from MainAppView for separation of concerns
extension YouTubeAPIService {
    /// Internal folder for persisted custom covers: ~/Library/Application Support/Swifttube/PlaylistCovers
    private func playlistCoversDirectory() throws -> URL {
        let fm = FileManager.default
        let appSupport = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = appSupport.appendingPathComponent("Swifttube/PlaylistCovers", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Remove any previously saved internal copy for this playlist (common image extensions).
    private func removeSavedCustomCoverIfExists(playlistId: String) {
        let fm = FileManager.default
        guard let dir = try? playlistCoversDirectory() else { return }
        let png = CacheKey(playlistId).hashedFilename(extension: "png")
        let jpg = CacheKey(playlistId).hashedFilename(extension: "jpg")
        let jpeg = CacheKey(playlistId).hashedFilename(extension: "jpeg")
        let candidates = [dir.appendingPathComponent(png), dir.appendingPathComponent(jpg), dir.appendingPathComponent(jpeg)]
        for u in candidates { if fm.fileExists(atPath: u.path) { _ = try? fm.removeItem(at: u) } }
    }

    /// Set one of the bundled default covers by logical name (e.g. "playlist3"). Clears any custom file path.
    @MainActor
    func setPlaylistCoverName(playlistId: String, name: String) {
        guard let idx = userPlaylists.firstIndex(where: { $0.id == playlistId }) else { return }
        // Clean up any previously saved internal custom image
        removeSavedCustomCoverIfExists(playlistId: playlistId)
        let p = userPlaylists[idx]
        let updated = YouTubePlaylist(
            id: p.id,
            title: p.title,
            description: p.description,
            thumbnailURL: p.thumbnailURL,
            videoCount: p.videoCount,
            videoIds: p.videoIds,
            coverName: name,
            customCoverPath: nil
        )
        userPlaylists[idx] = updated
    }

    /// Use a custom image file from disk. Clears the logical cover name.
    @MainActor
    func setPlaylistCustomCoverPath(playlistId: String, path: String) {
        guard let idx = userPlaylists.firstIndex(where: { $0.id == playlistId }) else { return }
        let p = userPlaylists[idx]

        // Create an internal persistent copy so the app keeps the image even if the original is deleted.
        let srcURL = URL(fileURLWithPath: path)
        let ext = srcURL.pathExtension.lowercased()
        let normalizedExt = ["png", "jpg", "jpeg"].contains(ext) ? ext : "png"
        let fm = FileManager.default
        var destURL: URL? = nil
        do {
            let dir = try playlistCoversDirectory()
            // Remove old copies (any extension) to avoid leftovers
            removeSavedCustomCoverIfExists(playlistId: playlistId)
            let filename = CacheKey(playlistId).hashedFilename(extension: normalizedExt)
            let candidate = dir.appendingPathComponent(filename)
            // Try to copy the file; if it fails, we'll fall back to referencing the original path
            if fm.fileExists(atPath: candidate.path) { try? fm.removeItem(at: candidate) }
            try fm.copyItem(at: srcURL, to: candidate)
            destURL = candidate
        } catch {
            destURL = nil
        }

        let storedPath = destURL?.path ?? path
        let updated = YouTubePlaylist(
            id: p.id,
            title: p.title,
            description: p.description,
            thumbnailURL: p.thumbnailURL,
            videoCount: p.videoCount,
            videoIds: p.videoIds,
            coverName: nil,
            customCoverPath: storedPath
        )
        userPlaylists[idx] = updated
    }

    /// Remove any custom file cover and reassign a random default.
    @MainActor
    func resetPlaylistCover(playlistId: String) {
        guard let idx = userPlaylists.firstIndex(where: { $0.id == playlistId }) else { return }
        // Clean up saved internal image
        removeSavedCustomCoverIfExists(playlistId: playlistId)
        let p = userPlaylists[idx]
        let updated = YouTubePlaylist(
            id: p.id,
            title: p.title,
            description: p.description,
            thumbnailURL: p.thumbnailURL,
            videoCount: p.videoCount,
            videoIds: p.videoIds,
            coverName: randomPlaylistCoverName(),
            customCoverPath: nil
        )
        userPlaylists[idx] = updated
    }
}
