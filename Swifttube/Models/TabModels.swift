/*
 Overview / Genel Bakış
 EN: Types for app tabs and payload (video/shorts) with optional playlist context.
 TR: Uygulama sekmeleri ve yükleri (video/shorts) için tipler; isteğe bağlı playlist bağlamıyla.
*/

// EN: Foundation for UUID, Codable. TR: UUID ve Codable için Foundation.
import Foundation

// EN: Tab content kind: video or shorts, carrying the target id. TR: Sekme içeriği türü: video veya shorts, hedef id ile.
enum TabKind: Equatable, Codable {
	case video(id: String)
	case shorts(id: String)
}

// EN: Optional playlist context when opened via playlist Play button. TR: Playlist Play ile açıldığında isteğe bağlı playlist bağlamı.
struct PlaylistContext: Equatable, Codable {
	// EN: Owning playlist id. TR: Bağlı playlist kimliği.
	let playlistId: String
}

struct AppTab: Identifiable, Equatable, Codable {
	// EN: Unique tab id. TR: Benzersiz sekme kimliği.
	let id: UUID
	// EN: Title shown on the tab strip. TR: Sekme şeridinde görünen başlık.
	var title: String
	// EN: Tab kind and target id. TR: Sekme türü ve hedef id.
	var kind: TabKind
	// EN: If set, the tab is in playlist mode and should render the playlist panel. TR: Ayarlıysa sekme playlist modundadır ve sağda panel gösterilmelidir.
	var playlist: PlaylistContext? = nil

	init(id: UUID = UUID(), title: String, kind: TabKind, playlist: PlaylistContext? = nil) {
		self.id = id
		self.title = title
		self.kind = kind
		self.playlist = playlist
	}
}

