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

// EN: Centralized Notification.Name constants for Shorts coordination and related events.
// TR: Shorts koordinasyonu ve ilgili olaylar için Notification.Name sabitlerinin merkezi tanımı.
// TODO: EN: Replace NotificationCenter with a Coordinator when migration stabilizes. TR: Geçiş oturduğunda NotificationCenter yerine Koordinatör kullan.
import Foundation

extension Notification.Name {
    // EN: Set focus to a specific Shorts video by id. TR: Belirli bir Shorts videosuna odaklan.
    static let shortsFocusVideoId = Notification.Name("shortsFocusVideoId")
    // EN: Clear Shorts focus (reset state). TR: Shorts odak durumunu sıfırla.
    static let shortsResetVideoId = Notification.Name("shortsResetVideoId")
    // EN: Stop all Shorts playback (when navigating away). TR: Tüm Shorts oynatmalarını durdur (sayfa değişince).
    static let shortsStopAll = Notification.Name("shortsStopAll")

    // EN: Navigation requests for Shorts (from compact window or per-video controls). TR: Shorts için gezinme istekleri (küçük pencereden veya video kontrollerinden).
    static let shortsRequestNext = Notification.Name("shortsRequestNext")
    static let shortsRequestPrev = Notification.Name("shortsRequestPrev")
    // EN: Toggle Shorts comments; userInfo: ["videoId": String]. TR: Shorts yorumlarını aç/kapat; userInfo: ["videoId": String].
    static let shortsToggleComments = Notification.Name("shortsToggleComments")

    // EN: Mark that user interacted with Shorts (e.g., disable autoplay heuristics). TR: Kullanıcı Shorts ile etkileşti (autoplay sezgisini devre dışı bırakmak için).
    static let userInteractedWithShorts = Notification.Name("userInteractedWithShorts")

    // EN: Player appearance toggles changed; update webviews without reload. TR: Oynatıcı görünüm ayarları değişti; webview'leri yeniden yüklemeden güncelle.
    static let playerAppearanceChanged = Notification.Name("playerAppearanceChanged")

    // EN: Mini (PiP-like) player closed; userInfo["videoId"] and optional ["time": Double]. TR: Mini (PiP benzeri) oynatıcı kapandı; userInfo["videoId"], opsiyonel ["time": Double].
    static let miniPlayerClosed = Notification.Name("miniPlayerClosed")
    // EN: Mini player opened; userInfo["videoId"]. TR: Mini oynatıcı açıldı; userInfo["videoId"].
    static let miniPlayerOpened = Notification.Name("miniPlayerOpened")

    // EN: Global navigation to default Home (used by tab strip Home button). TR: Varsayılan Ana Sayfa'ya global geçiş (sekme şeridi Ana Sayfa tuşu).
    static let goHome = Notification.Name("goHome")

    // EN: Stop a specific or all normal video embeds (tab close/navigation). TR: Belirli veya tüm normal video gömülerini durdur (sekme kapanışı/gezinme).
    static let stopVideoId = Notification.Name("stopVideoId")
    static let stopAllVideos = Notification.Name("stopAllVideos")

    // TR NOTE: Zaman atlama: userInfo["seconds"] zorunlu; opsiyonel userInfo["videoId"] olabilir.
    
    // EN: Open a video in playlist mode using tabs; userInfo: ["playlistId": String, "videoId"?: String, "index"?: Int]. TR: Sekmeli playlist modunda video aç; userInfo: ["playlistId": String, "videoId"?: String, "index"?: Int].
    static let openPlaylistMode = Notification.Name("openPlaylistMode")
    // EN: Open in overlay (non-tab) playlist mode; userInfo mirrors openPlaylistMode. TR: Kaplama (sekmesiz) playlist modunda aç; userInfo openPlaylistMode ile aynı.
    static let openPlaylistModeOverlay = Notification.Name("openPlaylistModeOverlay")
    // EN: Open a specific video within playlist mode from panel rows; userInfo: ["playlistId": String, "videoId": String]. TR: Panel satırlarından playlist modunda belirli videoyu aç; userInfo: ["playlistId": String, "videoId": String].
    static let openPlaylistVideo = Notification.Name("openPlaylistVideo")

    // EN: Show/hide bottom mini player bar (UI only). TR: Alt mini oynatıcı çubuğunu göster/gizle (yalnız UI).
    static let showBottomPlayerBar = Notification.Name("showBottomPlayerBar")
    static let hideBottomPlayerBar = Notification.Name("hideBottomPlayerBar")

    // EN: Start audio-only playlist playback; userInfo: ["playlistId": String, "index"?: Int]. TR: Yalnız ses playlist çalmayı başlat; userInfo: ["playlistId": String, "index"?: Int].
    static let startAudioPlaylist = Notification.Name("startAudioPlaylist")

    // EN: Open normal Video overlay from external controls; userInfo: ["videoId": String, "time"?: Double, "playlistId"?: String]. TR: Harici kontrollerden normal Video kaplaması aç; userInfo: ["videoId": String, "time"?: Double, "playlistId"?: String].
    static let openVideoOverlay = Notification.Name("openVideoOverlay")
}
