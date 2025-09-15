/*
 File Overview (EN)
 Purpose: Lightweight localization system providing Localizer environment object and string keys.
 Key Responsibilities:
 - Define localization keys and lookup
 - Offer .t(...) helper for views
 Used By: Most SwiftUI views for UI text.

 Dosya Özeti (TR)
 Amacı: Localizer ortam nesnesi ve metin anahtarlarını sağlayan hafif yerelleştirme sistemi.
 Ana Sorumluluklar:
 - Yerelleştirme anahtarlarını ve arama mekanizmasını tanımlamak
 - Görünümler için .t(...) yardımcısını sunmak
 Nerede Kullanılır: Çoğu SwiftUI görünümünde UI metinleri.
*/

import Foundation
import SwiftUI

// Lightweight runtime localization without Xcode .lproj setup
@MainActor
final class Localizer: ObservableObject {
    @AppStorage("appLanguage") var code: String = AppLanguage.en.rawValue {
        didSet { objectWillChange.send() }
    }

    var language: AppLanguage { AppLanguage(rawValue: code) ?? .en }

    enum Key: String, CaseIterable {
        case generalTab
        case appearanceTab
        case aboutTab
        case languageGroupTitle
        case languageAppLanguage
        case languageNote

        case cacheTitle
        case cacheDesc
        case clearImageCache
        case clearDataCache
    case clearAllData
    // Remember Tabs
    case rememberTabsTitle
    case rememberTabsDesc

    case confirmClearAllTitle
    case confirmClearAllMessage
        case confirmClearImageTitle
        case confirmClearImageMessage
        case confirmClearDataTitle
        case confirmClearDataMessage

        case apiKeyTitle
        case apiKeyDesc
        case save
        case paste
        case clear
        case saved
        case statusNoAPIKey
        case statusNoAPIKeyDesc
        case statusAPIKeyActive
        case statusAPIKeyActiveDesc

        case restartHint
        case restartApp
        case reset

        case searchPlaceholder
        case channels
        case playlists

        case sectionRecommended
        case sectionSearchResults
        case refresh
        case loading
        case shorts

    // Global/common
    case video
    case add
    case cancel
    case ok
    case delete
    case play
    case pause
    case more
    case share
    case comment
    case copyLink
    case openInNewTab
    case openInYouTube
    case readMore
    case showLess
    case showReplies
    case showMoreComments
    case allCommentsLoaded
    case status
    case showComments
    case hideComments

    // Navigation/Sidebar/Main
    case home
    case subscriptions
    case history
    case addChannel
    case addChannelURL

    // Filters/Search
    case search
    case date
    case duration
    case clearFilter
    case videoCountSuffix

    // Watch History
    case watchHistoryTitle
    case autoImport
    case noVideosYet
    case videosWillAppearHere
    case removeFromHistory
    case importYouTubeHistory
    case watchHistoryHTMLFile
    case dropTheFile
    case dragHTMLHere
    case historyHtmlExample
    case importHint
    case processingHtml
    case fileCouldNotBeRead
    case invalidFileType
    case successImported
    case done

    // Shorts/Comments/Common sections
    case comments
    case sortComments
    case reload
    case loadingShorts
    case noShortsFound

    // Sidebar/Sections/Tooltips
    case you
    case subscriptionsSection
    case searchChannel
    case searchPlaylist
    case closePanelHint
    case subscriptionsLoading
    case moreChannelsSuffix

    // Overlays / Errors
    case videosLoading
    case errorLabel

    // Related Videos
    case recommendedVideosTitle
    case recommendedLoading
    case recommendedNone

    // Categories
    case categoryTrending
    case categoryMusic
    case categoryGaming
    case categorySports
    case categoryNews
    case categoryEducation
    case categoryEntertainment
    case categoryTech
    case categoryComedy
    case categoryLifestyle

    // Actions / Labels
    case subscribe
    case unsubscribe
    case liveBadge
    case videos
    case allVideos
    case watching

    // Sorting / Titles
    case popularVideosTitle
    case sortVideos
    case showMoreVideos
    case latestVideosTitle

    // Comment sorting labels
    case sortMostLiked
    case sortNewest
    case sortRelevance

    // Subscriptions empty states / sections
    case noSubscriptionsYet
    case addSubscriptionsHint
    case subscriptionsShortsTitle

    // Add Channel panel (CSV import + manual URL)
    case dragCSVHere
    case orWord
    case enterChannelURL
    case channelURLPlaceholder
    case supportedFormats
    case supportedFormatHandle
    case supportedFormatC
    case supportedFormatChannelId
    case supportedFormatUser
    case processingCSV
    case invalidCSV
    case csvURLColumnNotFound
    case fileFormatNotSupported
    case fileLoadErrorPrefix
    case subscriptionsCSVHint
    case playlistsCSVHint
    case unsupportedFileType

    // Appearance (Player) settings
    case appearanceTopSection
    case appearanceTopHelp
    case appearanceTopChannelLogo
    case appearanceTopChannelName
    case appearanceTopVideoTitle
    case appearanceTopMoreVideosBox
    case appearanceTopContextMenu
    case appearanceTopWatchLater
    case appearanceTopShare

    case appearanceBottomSection
    case appearanceBottomHelp
    case appearanceBottomSubtitles
    case appearanceBottomQuality
    case appearanceBottomYouTubeLogo
    case appearanceBottomAirPlay
    case appearanceBottomChapterTitle
    case appearanceBottomScrubPreview
    // Algorithm / Location
    case algorithmTabTitle
    case algorithmLocationDesc
    // Custom Categories UI
    case customCategoryNewTitle
    case customCategoryName
    case customCategoryPrimary
    case customCategoryPrimarySingleWord
    case customCategorySecondary
    case customCategoryColor
    case customCategoryDefaultColor
    case customCategoryConfirm
    case customCategoryEdit
    case customCategoryThird
    case customCategoryFourth
    case customCategoryEmoji
    // Custom Category Date Filter options
    case customDateNone
    case customDateLastWeek
    case customDateLastMonth
    case customDateLastYear
    case customDateRandom
    // Custom Category Color names
    case customColorBlue
    case customColorGreen
    case customColorRed
    case customColorOrange
    case customColorPurple
    case customColorPink
    case customColorTeal
    case customColorYellow
    case customColorBrown
    // Video overlays / banners
    case pipModeBanner
    case fullscreenModeBanner
    
    // Playlists (context menus / rename)
    case playlistMenuDefaultCovers
    case playlistMenuUploadFromFile
    case playlistMenuResetToDefaults
    case playlistContextRename
    case playlistNamePlaceholder
    case choose
    // Playlist popover / toast
    case noPlaylistsYet
    case createNewPlaylist
    case addedToPlaylistToast
    }

    private let en: [Key: String] = [
        .generalTab: "General",
        .appearanceTab: "Appearance",
        .aboutTab: "About",
        .languageGroupTitle: "Language",
        .languageAppLanguage: "App language",
        .languageNote: "Some texts may update after restarting the app.",

        .cacheTitle: "Cache",
        .cacheDesc: "Manage image and data caches. Images load faster; data caches speed up searches and lists.",
        .clearImageCache: "Clear image cache",
        .clearDataCache: "Clear data cache",
    .clearAllData: "Clear all data",
    // Remember Tabs
    .rememberTabsTitle: "Remember tabs on startup",
    .rememberTabsDesc: "When enabled, the app re-opens the tabs that were open when you quit.",

    .confirmClearAllTitle: "Delete all data?",
    .confirmClearAllMessage: "This will remove all cached images and data, your watch history, and your subscriptions from this app. This action cannot be undone.",
        .confirmClearImageTitle: "Clear image cache?",
        .confirmClearImageMessage: "This will delete all cached images. They will be re-downloaded when needed.",
        .confirmClearDataTitle: "Clear data cache?",
        .confirmClearDataMessage: "This will delete all cached data used for searches and lists. Content will be fetched again as needed.",

        .apiKeyTitle: "YouTube API Key",
        .apiKeyDesc: "Enter an API key to load comments via the official YouTube API. If empty, comments won't load.",
        .save: "Save",
        .paste: "Paste",
        .clear: "Clear",
        .saved: "Saved",
        .statusNoAPIKey: "No API key",
        .statusNoAPIKeyDesc: "Comments disabled.",
        .statusAPIKeyActive: "API key active",
        .statusAPIKeyActiveDesc: "Length:",

        .restartHint: "Restart the app to fully apply changes.",
        .restartApp: "Restart App",
        .reset: "Reset",

        .searchPlaceholder: "Search",
        .channels: "Channels",
        .playlists: "Playlists",

        .sectionRecommended: "Recommended",
        .sectionSearchResults: "Search Results",
        .refresh: "Refresh",
        .loading: "Loading",
    .shorts: "Shorts",

    // Global/common
    .video: "Video",
    .add: "Add",
    .cancel: "Cancel",
    .ok: "OK",
    .delete: "Delete",
    .play: "Play",
    .pause: "Pause",
    .more: "More",
    .share: "Share",
    .comment: "Comment",
    .copyLink: "Copy Link",
    .openInNewTab: "Open in New Tab",
    .openInYouTube: "Open in YouTube",
    .readMore: "Read more",
    .showLess: "Show less",
    .showReplies: "Show replies",
    .showMoreComments: "Show more comments",
    .allCommentsLoaded: "All comments loaded",
    .status: "Status:",
    .showComments: "Show Comments",
    .hideComments: "Hide Comments",

    // Navigation/Sidebar/Main
    .home: "Home",
    .subscriptions: "Subscriptions",
    .history: "History",
    .addChannel: "Add Channel",
    .addChannelURL: "Add Channel URL",

    // Filters/Search
    .search: "Search",
    .date: "Date",
    .duration: "Duration",
    .clearFilter: "Clear",
    .videoCountSuffix: "video",

    // Watch History
    .watchHistoryTitle: "Watch History",
    .autoImport: "Auto Import",
    .noVideosYet: "You haven't watched any videos yet",
    .videosWillAppearHere: "Videos you watch will appear here",
    .removeFromHistory: "Remove from history",
    .importYouTubeHistory: "Import YouTube History",
    .watchHistoryHTMLFile: "Watch History HTML File",
    .dropTheFile: "Drop the file",
    .dragHTMLHere: "Drag the HTML file here",
    .historyHtmlExample: "watch-history.html",
    .importHint: "Drag the downloaded watch history HTML from YouTube to automatically add all watched videos.",
    .processingHtml: "Processing HTML file...",
    .fileCouldNotBeRead: "The file couldn't be read",
    .invalidFileType: "Invalid file type. Please choose an HTML file.",
    .successImported: "Imported successfully",
    .done: "Done",

    // Shorts/Comments/Common sections
    .comments: "Comments",
    .sortComments: "Sort comments",
    .reload: "Reload",
    .loadingShorts: "Loading shorts videos...",
    .noShortsFound: "No shorts found. Press ⌘R or use the menu to refresh.",

    // Sidebar/Sections/Tooltips
    .you: "You",
    .subscriptionsSection: "Subscriptions",
    .searchChannel: "Search Channel",
    .searchPlaylist: "Search Playlist",
    .closePanelHint: "Close open panel (Esc)",
    .subscriptionsLoading: "Loading subscriptions...",
    .moreChannelsSuffix: "more channels...",

    // Overlays / Errors
    .videosLoading: "Loading videos...",
    .errorLabel: "Error:",

    // Related Videos
    .recommendedVideosTitle: "Recommended Videos",
    .recommendedLoading: "Loading recommended videos...",
    .recommendedNone: "No recommended video found",

    // Categories
    .categoryTrending: "Trending",
    .categoryMusic: "Music",
    .categoryGaming: "Gaming",
    .categorySports: "Sports",
    .categoryNews: "News",
    .categoryEducation: "Education",
    .categoryEntertainment: "Entertainment",
    .categoryTech: "Technology",
    .categoryComedy: "Comedy",
    .categoryLifestyle: "Lifestyle",

    // Actions / Labels
    .subscribe: "Subscribe",
    .unsubscribe: "Unsubscribe",
    .liveBadge: "LIVE",
    .videos: "Videos",
    .allVideos: "All Videos",
    .watching: "watching",

    // Sorting / Titles
    .popularVideosTitle: "New Videos",
    .sortVideos: "Sort videos",
    .showMoreVideos: "Show more videos",
    .latestVideosTitle: "Latest Videos",

    // Comment sorting labels
    .sortMostLiked: "Most liked",
    .sortNewest: "Newest",
    .sortRelevance: "Relevance",

    // Subscriptions empty states / sections
    .noSubscriptionsYet: "No subscriptions yet",
    .addSubscriptionsHint: "You can add a channel URL from the sidebar to view your subscriptions",
    .subscriptionsShortsTitle: "Subscriptions Shorts",

    // Add Channel panel (CSV import + manual URL)
    .dragCSVHere: "Drag the CSV file here",
    .orWord: "or",
    .enterChannelURL: "Enter your channel URL:",
    .channelURLPlaceholder: "https://www.youtube.com/@username",
    .supportedFormats: "Supported formats:",
    .supportedFormatHandle: "• https://www.youtube.com/@username",
    .supportedFormatC: "• https://www.youtube.com/c/channelname",
    .supportedFormatChannelId: "• https://www.youtube.com/channel/CHANNEL_ID",
    .supportedFormatUser: "• https://www.youtube.com/user/username",
    .processingCSV: "Analyzing CSV file...",
    .invalidCSV: "Invalid CSV format",
    .csvURLColumnNotFound: "URL column not found in CSV",
    .fileFormatNotSupported: "File format not supported",
    .fileLoadErrorPrefix: "File load error",
    .subscriptionsCSVHint: "Drag the subscriptions CSV downloaded from YouTube to automatically add all your subscriptions.",
    .playlistsCSVHint: "Drag the playlists CSV downloaded from YouTube to automatically add all your playlists.",
    .unsupportedFileType: "Unsupported file type",

    // Appearance (Player) settings
    .appearanceTopSection: "Video Section (Top Bar)",
    .appearanceTopHelp: "You can hide items shown on the top bar of the YouTube player.",
    .appearanceTopChannelLogo: "Channel logo",
    .appearanceTopChannelName: "Channel name",
    .appearanceTopVideoTitle: "Video title",
    .appearanceTopMoreVideosBox: "'More videos' suggestion box",
    .appearanceTopContextMenu: "Right-click context menu",
    .appearanceTopWatchLater: "Watch later button",
    .appearanceTopShare: "Share button",

    .appearanceBottomSection: "Player Section (Bottom Controls)",
    .appearanceBottomHelp: "Check to hide the controls below.",
    .appearanceBottomSubtitles: "Subtitles button",
    .appearanceBottomQuality: "Quality (settings) button",
    .appearanceBottomYouTubeLogo: "YouTube logo",
    .appearanceBottomAirPlay: "AirPlay button",
    .appearanceBottomChapterTitle: "Middle (chapter) title",
    .appearanceBottomScrubPreview: "Scrub preview thumbnail",
    // Algorithm / Location
    .algorithmTabTitle: "Location",
    .algorithmLocationDesc: "Select a location to tailor Home, Shorts, and Search results. If Global is selected, no country bias is applied.",
    // Custom Categories UI
    .customCategoryNewTitle: "New Custom Category",
    .customCategoryName: "Name",
    .customCategoryPrimary: "Primary keyword (single word)",
    .customCategoryPrimarySingleWord: "Primary keyword must be a single word",
    .customCategorySecondary: "Secondary keyword (optional)",
    .customCategoryColor: "Color:",
    .customCategoryDefaultColor: "Default",
    .customCategoryConfirm: "Confirm",
    .customCategoryEdit: "Edit",
    .customCategoryThird: "3rd keyword (optional)",
    .customCategoryFourth: "4th keyword (optional)",
    .customCategoryEmoji: "Add emoji"
    ,
    // Custom Category Date Filter options
    .customDateNone: "(None)",
    .customDateLastWeek: "1 Week",
    .customDateLastMonth: "1 Month",
    .customDateLastYear: "1 Year",
    .customDateRandom: "Random"
    ,
    // Custom Category Colors
    .customColorBlue: "Blue",
    .customColorGreen: "Green",
    .customColorRed: "Red",
    .customColorOrange: "Orange",
    .customColorPurple: "Purple",
    .customColorPink: "Pink",
    .customColorTeal: "Teal",
    .customColorYellow: "Yellow",
    .customColorBrown: "Brown"
    ,
    // Video overlays / banners
    .pipModeBanner: "Video is in PiP mode",
    .fullscreenModeBanner: "Video is in Fullscreen mode"
    ,
    // Playlists (context menus / rename)
    .playlistMenuDefaultCovers: "Default cover images",
    .playlistMenuUploadFromFile: "Upload from file…",
    .playlistMenuResetToDefaults: "Reset to defaults",
    .playlistContextRename: "Rename",
    .playlistNamePlaceholder: "Playlist name",
    .choose: "Choose",
    // Playlist popover / toast
    .noPlaylistsYet: "No playlists yet",
    .createNewPlaylist: "Create new playlist",
    .addedToPlaylistToast: "Added to playlist"
    ]

    private let tr: [Key: String] = [
        .generalTab: "Genel",
        .appearanceTab: "Görünüm",
        .aboutTab: "Hakkında",
        .languageGroupTitle: "Dil",
        .languageAppLanguage: "Uygulama dili",
        .languageNote: "Bazı metinler uygulama yeniden başlatılınca güncellenir.",

        .cacheTitle: "Önbellek",
        .cacheDesc: "Görsel ve veri önbelleğini yönetebilirsiniz. Görseller daha hızlı yüklenir, veri cache'leri arama ve listeler için tekrar kullanım sağlar.",
        .clearImageCache: "Görsel önbelleği temizle",
        .clearDataCache: "Veri önbelleğini temizle",
    .clearAllData: "Tüm verileri sil",
    // Remember Tabs
    .rememberTabsTitle: "Sekmeleri açılışta hatırla",
    .rememberTabsDesc: "Etkinse, uygulamadan çıkarken açık olan sekmeler bir sonraki açılışta tekrar açılır.",

    .confirmClearAllTitle: "Tüm veriler silinsin mi?",
    .confirmClearAllMessage: "Bu işlem uygulamadaki tüm görsel ve veri önbelleğini, izleme geçmişini ve aboneliklerinizi silecek. Bu işlem geri alınamaz.",
        .confirmClearImageTitle: "Görsel önbelleği temizlensin mi?",
        .confirmClearImageMessage: "Önbelleğe alınmış tüm görseller silinecek. Gerektikçe yeniden indirilecek.",
        .confirmClearDataTitle: "Veri önbelleği temizlensin mi?",
        .confirmClearDataMessage: "Arama ve listeler için kullanılan tüm önbelleğe alınmış veriler silinecek. İçerikler ihtiyaç olduğunda yeniden yüklenecek.",

        .apiKeyTitle: "YouTube API Key",
        .apiKeyDesc: "Yorumları resmi YouTube API üzerinden çekmek için bir API key girin. Boş bırakılırsa yorumlar yüklenmez.",
        .save: "Kaydet",
        .paste: "Yapıştır",
        .clear: "Temizle",
        .saved: "Kaydedildi",
        .statusNoAPIKey: "API key yok",
        .statusNoAPIKeyDesc: "Yorumlar devre dışı.",
        .statusAPIKeyActive: "API key etkin",
        .statusAPIKeyActiveDesc: "Uzunluk:",

        .restartHint: "Değişikliklerin uygulanması için uygulamayı yeniden başlatın.",
        .restartApp: "Uygulamayı Yeniden Başlat",
        .reset: "Sıfırla",

        .searchPlaceholder: "Ara",
        .channels: "Kanallar",
        .playlists: "Oynatma Listesi",

        .sectionRecommended: "Önerilen",
        .sectionSearchResults: "Arama Sonuçları",
        .refresh: "Yenile",
        .loading: "Yükleniyor",
    .shorts: "Shorts",

    // Global/common
    .video: "Video",
    .add: "Ekle",
    .cancel: "İptal",
    .ok: "Tamam",
    .delete: "Sil",
    .play: "Oynat",
    .pause: "Durdur",
    .more: "Daha",
    .share: "Paylaş",
    .comment: "Yorum",
    .copyLink: "Bağlantıyı Kopyala",
    .openInNewTab: "Yeni Sekmede Aç",
    .openInYouTube: "YouTube'da Aç",
    .readMore: "Devamını Oku",
    .showLess: "Daha Az Göster",
    .showReplies: "Yanıtları Göster",
    .showMoreComments: "Daha Fazla Yorum Göster",
    .allCommentsLoaded: "Tüm Yorumlar Yüklendi",
    .status: "Durum:",
    .showComments: "Yorumları Göster",
    .hideComments: "Yorumları Gizle",

    // Navigation/Sidebar/Main
    .home: "Ana Sayfa",
    .subscriptions: "Abonelikler",
    .history: "Geçmiş",
    .addChannel: "Kanal Ekle",
    .addChannelURL: "Kanal URL'si ekle",

    // Filters/Search
    .search: "Ara",
    .date: "Tarih",
    .duration: "Süre",
    .clearFilter: "Temizle",
    .videoCountSuffix: "video",

    // Watch History
    .watchHistoryTitle: "İzleme Geçmişi",
    .autoImport: "Otomatik Ekle",
    .noVideosYet: "Henüz video izlemediniz",
    .videosWillAppearHere: "İzlediğiniz videolar burada görünecek",
    .removeFromHistory: "Geçmişten Sil",
    .importYouTubeHistory: "YouTube Geçmişini İçe Aktar",
    .watchHistoryHTMLFile: "İzleme Geçmişi HTML Dosyası",
    .dropTheFile: "Dosyayı bırakın",
    .dragHTMLHere: "HTML dosyasını buraya sürükleyin",
    .historyHtmlExample: "izleme geçmişi.html",
    .importHint: "YouTube'dan indirilen izleme geçmişi HTML dosyasını sürükleyerek tüm izlediğiniz videoları otomatik olarak ekleyebilirsiniz.",
    .processingHtml: "HTML dosyası işleniyor...",
    .fileCouldNotBeRead: "Dosya okunamadı",
    .invalidFileType: "Geçersiz dosya türü. Lütfen HTML dosyası seçin.",
    .successImported: "Başarıyla içe aktarıldı",
    .done: "Tamam",

    // Shorts/Comments/Common sections
    .comments: "Yorumlar",
    .sortComments: "Yorumları sırala",
    .reload: "Tekrar Yükle",
    .loadingShorts: "Shorts videoları yükleniyor...",
    .noShortsFound: "Shorts bulunamadı. Yeniden denemek için ⌘R veya menüden yenile.",

    // Sidebar/Sections/Tooltips
    .you: "Siz",
    .subscriptionsSection: "Abonelikler",
    .searchChannel: "Kanal Ara",
    .searchPlaylist: "Playlist Ara",
    .closePanelHint: "Açık paneli kapat (Esc)",
    .subscriptionsLoading: "Abonelikler yükleniyor...",
    .moreChannelsSuffix: "daha fazla kanal...",

    // Overlays / Errors
    .videosLoading: "Videolar yükleniyor...",
    .errorLabel: "Hata:",

    // Related Videos
    .recommendedVideosTitle: "Önerilen Videolar",
    .recommendedLoading: "Önerilen videolar yükleniyor...",
    .recommendedNone: "Önerilen video bulunamadı",
    // Actions / Labels
    .subscribe: "Abone Ol",
    .unsubscribe: "Abonelikten Çık",
    .liveBadge: "CANLI",
    .videos: "Videolar",
    .allVideos: "Tüm Videolar",
    .watching: "izleyici",

    // Sorting / Titles
    .popularVideosTitle: "Yeni Videolar",
    .sortVideos: "Videoları sırala",
    .showMoreVideos: "Daha fazla video göster",
    .latestVideosTitle: "En Yeni Videolar",

    // Comment sorting labels
    .sortMostLiked: "En çok beğeni",
    .sortNewest: "En yeni",
    .sortRelevance: "İlgililik",

    // Subscriptions empty states / sections
    .noSubscriptionsYet: "Henüz abonelik bulunmuyor",
    .addSubscriptionsHint: "Aboneliklerinizi görüntülemek için Sidebar'dan kanal URL'si ekleyebilirsiniz",
    .subscriptionsShortsTitle: "Abonelik Shorts",

    // Add Channel panel (CSV import + manual URL)
    .dragCSVHere: "CSV dosyasını buraya sürükleyin",
    .orWord: "veya",
    .enterChannelURL: "Kanal URL'nizi girin:",
    .channelURLPlaceholder: "https://www.youtube.com/@kullaniciadi",
    .supportedFormats: "Desteklenen formatlar:",
    .supportedFormatHandle: "• https://www.youtube.com/@kullaniciadi",
    .supportedFormatC: "• https://www.youtube.com/c/kanaladi",
    .supportedFormatChannelId: "• https://www.youtube.com/channel/CHANNEL_ID",
    .supportedFormatUser: "• https://www.youtube.com/user/kullaniciadi",
    .processingCSV: "CSV dosyası analiz ediliyor...",
    .invalidCSV: "Geçersiz CSV formatı",
    .csvURLColumnNotFound: "CSV'de URL kolonu bulunamadı",
    .fileFormatNotSupported: "Dosya formatı desteklenmiyor",
    .fileLoadErrorPrefix: "Dosya yükleme hatası",
    .subscriptionsCSVHint: "YouTube'dan indirilen abonelik CSV dosyasını sürükleyerek tüm aboneliklerinizi otomatik olarak ekleyebilirsiniz.",
    .playlistsCSVHint: "YouTube'dan indirilen oynatma listeleri CSV dosyasını sürükleyerek tüm listelerinizi otomatik olarak ekleyebilirsiniz.",
    .unsupportedFileType: "Desteklenmeyen dosya türü",

    // Appearance (Player) settings
    .appearanceTopSection: "Video Bölümü (Üst Alan)",
    .appearanceTopHelp: "YouTube oynatıcısının üst çubuğunda görünen öğeleri gizleyebilirsiniz.",
    .appearanceTopChannelLogo: "Kanal logosu",
    .appearanceTopChannelName: "Kanal adı",
    .appearanceTopVideoTitle: "Video ismi",
    .appearanceTopMoreVideosBox: "'Daha fazla video' öneri kutusu",
    .appearanceTopContextMenu: "Sağ tık context menüsü",
    .appearanceTopWatchLater: "Daha sonra izle butonu",
    .appearanceTopShare: "Paylaş butonu",

    .appearanceBottomSection: "Oynatıcı Bölümü (Alt Kontroller)",
    .appearanceBottomHelp: "Aşağıdaki kontrolleri gizlemek için işaretleyin.",
    .appearanceBottomSubtitles: "Altyazı butonu",
    .appearanceBottomQuality: "Kalite (ayarlar) butonu",
    .appearanceBottomYouTubeLogo: "YouTube logosu",
    .appearanceBottomAirPlay: "AirPlay butonu",
    .appearanceBottomChapterTitle: "Orta bölüm (chapter) başlığı",
    .appearanceBottomScrubPreview: "Çubuk önizleme resmi",
    // Algorithm / Location
    .algorithmTabTitle: "Konum",
    .algorithmLocationDesc: "Ana Sayfa, Shorts ve Arama sonuçlarını ülkeye göre uyarlayın. Global seçiliyse ülke etkisi uygulanmaz.",
    // Custom Categories UI
    .customCategoryNewTitle: "Yeni Özel Kategori",
    .customCategoryName: "İsim",
    .customCategoryPrimary: "Ana kelime (tek kelime)",
    .customCategoryPrimarySingleWord: "Ana kelime tek bir kelime olmalı",
    .customCategorySecondary: "İkinci kelime (isteğe bağlı)",
    .customCategoryColor: "Renk:",
    .customCategoryDefaultColor: "Varsayılan",
    .customCategoryConfirm: "Onayla",
    .customCategoryEdit: "Düzenle",
    .customCategoryThird: "3. kelime (isteğe bağlı)",
    .customCategoryFourth: "4. kelime (isteğe bağlı)",
    .customCategoryEmoji: "Emoji ekle"
    ,
    // Custom Category Date Filter options
    .customDateNone: "(Yok)",
    .customDateLastWeek: "1 Hafta",
    .customDateLastMonth: "1 Ay",
    .customDateLastYear: "1 Yıl",
    .customDateRandom: "Rastgele"
    ,
    // Custom Category Colors
    .customColorBlue: "Mavi",
    .customColorGreen: "Yeşil",
    .customColorRed: "Kırmızı",
    .customColorOrange: "Turuncu",
    .customColorPurple: "Mor",
    .customColorPink: "Pembe",
    .customColorTeal: "Turkuaz",
    .customColorYellow: "Sarı",
    .customColorBrown: "Kahverengi"
    ,
    // Video overlays / banners
    .pipModeBanner: "Video PiP modunda",
    .fullscreenModeBanner: "Video tam ekran modunda"
    ,
    // Playlists (context menus / rename)
    .playlistMenuDefaultCovers: "Varsayılan kapak fotoğrafları",
    .playlistMenuUploadFromFile: "Dosyadan yükle…",
    .playlistMenuResetToDefaults: "Varsayılanlara sıfırla",
    .playlistContextRename: "Adı değiştir",
    .playlistNamePlaceholder: "Playlist adı",
    .choose: "Seç",
    // Playlist popover / toast
    .noPlaylistsYet: "Henüz playlist yok",
    .createNewPlaylist: "Yeni playlist oluştur",
    .addedToPlaylistToast: "Playlist'e eklendi"
    ]

    func t(_ key: Key) -> String {
        switch language {
        case .en: return en[key] ?? key.rawValue
        case .tr: return tr[key] ?? key.rawValue
        }
    }
}
