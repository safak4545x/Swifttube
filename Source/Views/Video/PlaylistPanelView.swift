/*
 File Overview (EN)
 Purpose: Right-side playlist panel in video pages; shows playlist title, items, and supports play/scroll synchronization.
 Key Responsibilities:
 - Render playlist items with selection highlighting and scroll-to-current
 - Support lazy loading of remaining items and show total count/footer
 - Interact with player to jump to selected video
 Used By: Video pages in playlist mode and overlay playlist panels.

 Dosya Özeti (TR)
 Amacı: Video sayfalarında sağdaki oynatma listesi paneli; liste başlığı, öğeler ve oynatma/kaydırma senkronizasyonunu destekler.
 Ana Sorumluluklar:
 - Seçim vurgusu ve geçerli öğeye kaydırma ile liste öğelerini göstermek
 - Kalan öğeleri tembel yükleme ve toplam sayıyı/alt bilgi çubuğunu göstermek
 - Seçilen videoya atlamak için oynatıcıyla etkileşmek
 Nerede Kullanılır: Playlist modundaki video sayfaları ve overlay playlist panelleri.
*/

import SwiftUI
