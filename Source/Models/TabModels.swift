/*
 File Overview (EN)
 Purpose: Types that represent application tabs and their payload (video/shorts) with optional playlist context.
 Key Responsibilities:
 - Define TabKind (video/shorts) and AppTab identity (id, title, kind)
 - Carry optional PlaylistContext to enable playlist-aware UI on video pages
 Used By: TabCoordinator, TabHostView, VideoDetailView.

 Dosya Özeti (TR)
 Amacı: Uygulama sekmelerini ve yüklerini (video/shorts) opsiyonel playlist bağlamıyla birlikte tanımlayan tipler.
 Ana Sorumluluklar:
 - TabKind (video/shorts) ve AppTab kimliğini (id, başlık, tür) tanımlamak
 - Video sayfalarında playlist odaklı UI'ı etkinleştirmek için PlaylistContext taşımak
 Nerede Kullanılır: TabCoordinator, TabHostView, VideoDetailView.
*/

import Foundation

enum TabKind: Equatable, Codable {
	case video(id: String)
	case shorts(id: String)
}

// Optional playlist context carried by a tab when opened from the playlist Play button
struct PlaylistContext: Equatable, Codable {
	let playlistId: String
}

struct AppTab: Identifiable, Equatable, Codable {
	let id: UUID
	var title: String
	var kind: TabKind
	// If not nil, this tab is in "playlist mode" and VideoDetailView should render the playlist panel on the right
	var playlist: PlaylistContext? = nil

	init(id: UUID = UUID(), title: String, kind: TabKind, playlist: PlaylistContext? = nil) {
		self.id = id
		self.title = title
		self.kind = kind
		self.playlist = playlist
	}
}

