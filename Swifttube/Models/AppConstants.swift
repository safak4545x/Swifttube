
/*
 Overview / Genel Bakış
 EN: App-wide constants: sidebar items and defaults reused across modules.
 TR: Uygulama genel sabitleri: modüllerde tekrar kullanılan yan menü öğeleri ve varsayılanlar.
*/

import Foundation

// EN: Default sidebar items shown in the native Sidebar. TR: Yerel Sidebar'da gösterilen varsayılan yan menü öğeleri.
let sidebarItems = [
    // EN: Home page. TR: Ana Sayfa.
    SidebarItem(systemName: "house.fill", title: "Ana Sayfa", url: "https://www.youtube.com/"),
    // EN: Shorts page. TR: Shorts sayfası.
    SidebarItem(
        systemName: "play.square.fill", title: "Shorts", url: "https://www.youtube.com/shorts"),
    // EN: Subscriptions feed. TR: Abonelikler akışı.
    SidebarItem(
        systemName: "rectangle.stack.person.crop.fill", title: "Abonelikler",
        url: "https://www.youtube.com/feed/subscriptions"),
    // EN: Playlists hub (new entry). TR: Oynatma listesi merkezi (yeni).
    SidebarItem(
        systemName: "music.note.list", title: "Oynatma Listesi",
        url: "https://www.youtube.com/feed/playlists"),
    // EN: You page (account area). TR: Siz sayfası (hesap alanı).
    SidebarItem(
        systemName: "person.crop.circle", title: "Siz", url: "https://www.youtube.com/feed/you"),
    // EN: Watch History. TR: İzleme Geçmişi.
    SidebarItem(
        systemName: "clock.arrow.circlepath", title: "Geçmiş",
        url: "https://www.youtube.com/feed/history"),

]
 
