
/*
 File Overview (EN)
 Purpose: Playlist search and video fetch operations using local adapters, with optional official count enrichment.
 Key Responsibilities:
 - Search playlists and fetch playlist videos via LocalPlaylistAdapter
 - Request authoritative item counts from Official API and merge later
 - Maintain YouTubeAPIService flags for loading and store results for UI
 Used By: Playlist search UI and PlaylistView.

 Dosya Özeti (TR)
 Amacı: Yerel adaptörlerle playlist arama ve video getirme; gerekirse resmi API ile öğe sayısı zenginleştirme.
 Ana Sorumluluklar:
 - LocalPlaylistAdapter ile playlist aramak ve videolarını çekmek
 - Resmi API'den gelen kesin öğe sayısını daha sonra birleştirmek
 - YouTubeAPIService üzerinde yükleniyor bayraklarını yönetmek ve sonuçları UI için tutmak
 Nerede Kullanılır: Playlist arama arayüzü ve PlaylistView.
*/


import Foundation

// MARK: - Playlist Service
extension YouTubeAPIService {
    
    func searchPlaylists(query: String) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            searchedPlaylists = []
            isSearching = false
            return
        }
        isSearching = true
        searchedPlaylists = []
        Task { @MainActor in
            do {
                let items = try await LocalPlaylistAdapter.search(query: q)
                self.searchedPlaylists = items
                // Request authoritative counts via official API (batched)
                self.queuePlaylistCountFetch(items.map { $0.id })
            } catch {
                print("⚠️ Playlist search failed: \(error)")
                self.searchedPlaylists = []
            }
            self.isSearching = false
        }
    }
    
    func fetchPlaylistVideos(playlistId: String) {
        guard !playlistId.isEmpty else { return }
        isLoading = true
        playlistVideos = []
        Task { @MainActor in
            do {
                let items = try await LocalPlaylistAdapter.fetchVideos(playlistId: playlistId, limit: 50)
                self.playlistVideos = items
            } catch {
                print("⚠️ Fetch playlist videos failed: \(error)")
                self.playlistVideos = []
            }
            self.isLoading = false
        }
    }
}
