
/*
 File Overview (EN)
 Purpose: Centralized app-wide constants such as limits, defaults, and feature flags.
 Key Responsibilities:
 - Provide static constants for reuse across modules
 - Document default values affecting UI and services
 Used By: Views and Services throughout the app.

 Dosya Özeti (TR)
 Amacı: Limitler, varsayılanlar ve özellik bayrakları gibi uygulama genel sabitlerini merkezileştirmek.
 Ana Sorumluluklar:
 - Modüller arası yeniden kullanılan statik sabitleri sağlamak
 - UI ve servisleri etkileyen varsayılan değerleri belgelemek
 Nerede Kullanılır: Uygulama genelinde Views ve Services.
*/

import Foundation

let sidebarItems = [
    SidebarItem(systemName: "house.fill", title: "Ana Sayfa", url: "https://www.youtube.com/"),
    SidebarItem(
        systemName: "play.square.fill", title: "Shorts", url: "https://www.youtube.com/shorts"),
    SidebarItem(
        systemName: "rectangle.stack.person.crop.fill", title: "Abonelikler",
        url: "https://www.youtube.com/feed/subscriptions"),
    // Yeni eklenen: Oynatma listesi (Playlists)
    SidebarItem(
        systemName: "music.note.list", title: "Oynatma Listesi",
        url: "https://www.youtube.com/feed/playlists"),
    SidebarItem(
        systemName: "person.crop.circle", title: "Siz", url: "https://www.youtube.com/feed/you"),
    SidebarItem(
        systemName: "clock.arrow.circlepath", title: "Geçmiş",
        url: "https://www.youtube.com/feed/history"),

]
 
