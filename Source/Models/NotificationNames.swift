/*
 File Overview (EN)
 Purpose: Centralize Notification.Name keys used across the app for Shorts, navigation, mini player, and overlay coordination.
 Key Responsibilities:
 - Declare typed Notification.Name constants for publish/observe patterns
 - Document intended userInfo payloads to reduce misuse across modules
 - Provide a single import point to avoid stringly-typed duplication
 Used By: Shorts views/controllers, mini player windows, navigation handlers, and video overlays.

 Dosya Özeti (TR)
 Amacı: Uygulama genelinde Shorts, gezinme, mini oynatıcı ve katman koordinasyonu için kullanılan Notification.Name anahtarlarını merkezileştirir.
 Ana Sorumluluklar:
 - Yayınlama/izleme desenleri için türlenmiş Notification.Name sabitlerini tanımlamak
 - Modüller arasında yanlış kullanımı azaltmak için beklenen userInfo içeriklerini belgelendirmek
 - String tabanlı tekrarları önlemek için tek bir tanım noktası sunmak
 Nerede Kullanılır: Shorts görünümleri/kontrolörleri, mini oynatıcı pencereleri, gezinme yöneticileri ve video katmanları.
*/

// Centralized Notification.Name constants for Shorts coordination and related events.
// TODO: Replace NotificationCenter usage with an ObservableObject/Coordinator once migration stabilizes.
import Foundation

extension Notification.Name {
    // Shorts focus & lifecycle
    static let shortsFocusVideoId = Notification.Name("shortsFocusVideoId")
    static let shortsResetVideoId = Notification.Name("shortsResetVideoId")
    static let shortsStopAll = Notification.Name("shortsStopAll")

    // Navigation requests (triggered from compact window or per-video controls)
    static let shortsRequestNext = Notification.Name("shortsRequestNext")
    static let shortsRequestPrev = Notification.Name("shortsRequestPrev")
    // Toggle Shorts comments (userInfo: ["videoId": String])
    static let shortsToggleComments = Notification.Name("shortsToggleComments")

    // User interaction heuristic (e.g., to suppress autoplay logic after manual control)
    static let userInteractedWithShorts = Notification.Name("userInteractedWithShorts")

    // Player appearance toggles changed (to update existing webviews without reload)
    static let playerAppearanceChanged = Notification.Name("playerAppearanceChanged")

    // Mini (PiP benzeri) oynatıcı kapandığında tetiklenir; userInfo["videoId"] içerir
    static let miniPlayerClosed = Notification.Name("miniPlayerClosed")
    // Mini oynatıcı açıldığında tetiklenir; userInfo["videoId"] içerir
    static let miniPlayerOpened = Notification.Name("miniPlayerOpened")

    // Global navigation: Go to default Home page (used by the leftmost Home button in tab strip)
    static let goHome = Notification.Name("goHome")

    // Normal video embed lifecycle: stop specific or all videos (tab close, navigation etc.)
    static let stopVideoId = Notification.Name("stopVideoId")
    static let stopAllVideos = Notification.Name("stopAllVideos")

    // Zaman atlama: userInfo["seconds"] zorunlu; opsiyonel olarak userInfo["videoId"] olabilir
    
    // Open a video panel in playlist mode; userInfo requires ["playlistId": String]
    static let openPlaylistMode = Notification.Name("openPlaylistMode")
    // Open in overlay (non-tab) playlist mode; userInfo requires ["playlistId": String]
    static let openPlaylistModeOverlay = Notification.Name("openPlaylistModeOverlay")
    static let openPlaylistVideo = Notification.Name("openPlaylistVideo")

    // Bottom player bar (UI-only placeholder toggle)
    static let showBottomPlayerBar = Notification.Name("showBottomPlayerBar")
    static let hideBottomPlayerBar = Notification.Name("hideBottomPlayerBar")

    // Audio-only playlist playback control
    static let startAudioPlaylist = Notification.Name("startAudioPlaylist")

    // Open normal Video panel (overlay) from external controls (e.g., mini player)
    // userInfo: ["videoId": String, "time": Double? (seconds), "playlistId": String?]
    static let openVideoOverlay = Notification.Name("openVideoOverlay")
}
