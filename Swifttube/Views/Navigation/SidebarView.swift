/*
 Overview / Genel Bakış
 EN: Legacy/custom sidebar listing core pages and user subscriptions; replaced by native sidebar in MainContentView.
 TR: Çekirdek sayfalar ve abonelikleri listeleyen eski/özel yan menü; MainContentView’de yerel sidebar ile değiştirildi.
*/

// EN: SwiftUI-based sidebar list. TR: SwiftUI tabanlı yan menü listesi.
import SwiftUI

// EN: Legacy sidebar for navigation and subscriptions. TR: Gezinme ve abonelikler için eski yan menü.
struct SidebarView: View {
		// EN: Localizer for labels. TR: Etiketler için yerelleştirici.
		@EnvironmentObject var i18n: Localizer
    // EN: Currently selected sidebar item id. TR: Geçerli seçili yan menü öğe id'si.
    @Binding var selectedSidebarId: String
    // EN: Current URL corresponding to selection. TR: Seçime karşılık gelen geçerli URL.
    @Binding var currentURL: String
    // EN: Controls channel URL input sheet visibility. TR: Kanal URL giriş sayfası görünürlüğü.
    @Binding var showUserChannelInput: Bool
    // EN: API service carrying subscriptions/loading flags. TR: Abonelikler/yükleme bayraklarını taşıyan API servisi.
    @ObservedObject var youtubeAPI: YouTubeAPIService
    
    // EN: Dynamic, localized sidebar items. TR: Dinamik, yerelleştirilmiş yan menü öğeleri.
    private var localizedSidebarItems: [SidebarItem] {
        [
            SidebarItem(systemName: "house.fill", title: i18n.t(.home), url: "https://www.youtube.com/"),
            SidebarItem(systemName: "play.square.fill", title: i18n.t(.shorts), url: "https://www.youtube.com/shorts"),
            SidebarItem(systemName: "rectangle.stack.person.crop.fill", title: i18n.t(.subscriptions), url: "https://www.youtube.com/feed/subscriptions"),
            SidebarItem(systemName: "music.note.list", title: i18n.t(.playlists), url: "https://www.youtube.com/feed/playlists"),
            SidebarItem(systemName: "person.crop.circle", title: i18n.t(.you), url: "https://www.youtube.com/feed/you"),
            SidebarItem(systemName: "clock.arrow.circlepath", title: i18n.t(.history), url: "https://www.youtube.com/feed/history")
        ]
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // EN: Top static navigation items. TR: Üstteki statik gezinme öğeleri.
            ForEach(localizedSidebarItems) { item in
                Button(action: {
                    // EN: Update selection and drive content fetch. TR: Seçimi güncelle ve içerik çekimini tetikle.
                    selectedSidebarId = item.id
                    currentURL = item.url
                    // EN: Load Shorts feed when entering Shorts. TR: Shorts sayfasına girince Shorts akışını yükle.
                    if item.url == "https://www.youtube.com/shorts" {
                        youtubeAPI.fetchShortsVideos(suppressOverlay: false)
                    } else {
                        // EN: On Home, prefer selected custom category else default recommendations.
                        // TR: Ana sayfada, seçili özel kategori varsa onu; yoksa varsayılan öneriler.
                        if let sel = youtubeAPI.selectedCustomCategoryId,
                           let custom = youtubeAPI.customCategories.first(where: { $0.id == sel }) {
                            youtubeAPI.fetchVideos(for: custom)
                        } else {
                            youtubeAPI.fetchHomeRecommendations()
                        }
                    }
                }) {
                    HStack(alignment: .center, spacing: 10) {
                        HStack(alignment: .center, spacing: 10) {
                            Image(systemName: item.systemName)
                                .foregroundColor(
                                    selectedSidebarId == item.id ? .accentColor : .secondary)
                            Text(item.title)
                                .foregroundColor(
                                    selectedSidebarId == item.id ? .accentColor : .primary)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(
                            selectedSidebarId == item.id
                                ? Color.accentColor.opacity(0.15) : Color.clear
                        )
                        .cornerRadius(8)
                        Spacer()  // EN: Keep labels left-aligned. TR: Yazıları sola yasla.
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // EN: Subscriptions section. TR: Abonelikler bölümü.
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                HStack {
                    Text(i18n.t(.subscriptions))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: {
                        showUserChannelInput = true
                    }) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 8)
                .padding(.trailing, 8)
                
                // EN: Loading state for user data. TR: Kullanıcı verisi yükleme durumu.
                if youtubeAPI.isLoadingUserData {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 20, height: 20)
                        Text(i18n.t(.subscriptionsLoading))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 8)
                }
                
                // EN: User channel from URL + derived subscriptions. TR: URL'den alınan kullanıcı kanalı + türetilen abonelikler.
                if youtubeAPI.userChannelFromURL != nil {
                    VStack(alignment: .leading, spacing: 4) {
                        // EN: Show first 10 subscriptions. TR: İlk 10 aboneliği göster.
                        ForEach(youtubeAPI.userSubscriptionsFromURL.prefix(10)) { channel in
                            HStack(spacing: 8) {
                                CachedAsyncImage(url: URL(string: channel.thumbnailURL)) { image in
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Circle().fill(Color.gray.opacity(0.3))
                                }
                                .frame(width: 20, height: 20)
                                .clipShape(Circle())
                                Text(channel.title)
                                    .font(.system(size: 11))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.vertical, 1)
                            .padding(.horizontal, 8)
                            .contentShape(Rectangle())
                        }
                        
                        // EN: Show a "more" row when subscriptions exceed 10. TR: 10'dan fazla olduğunda "daha fazla" satırı göster.
                        if youtubeAPI.userSubscriptionsFromURL.count > 10 {
                            HStack(spacing: 8) {
                                Image(systemName: "ellipsis")
                                    .frame(width: 20, height: 20)
                                    .foregroundColor(.secondary)
                                Text("\(youtubeAPI.userSubscriptionsFromURL.count - 10) \(i18n.t(.moreChannelsSuffix))")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.vertical, 1)
                            .padding(.horizontal, 8)
                        }
                    }
                } else if youtubeAPI.isLoadingUserData {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.5)
                        Text(i18n.t(.loading))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                } else {
                    // EN: Prompt user to add a channel URL. TR: Kullanıcıya kanal URL'si eklet.
                    Button(action: {
                        showUserChannelInput = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "link")
                                .font(.system(size: 12))
                                .foregroundColor(.blue)
                            Text(i18n.t(.addChannelURL))
                                .font(.system(size: 11))
                                .foregroundColor(.blue)
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
                
                // EN: Show parsing/network error for user channel. TR: Kullanıcı kanalı için ayrıştırma/ağ hatasını göster.
                if let error = youtubeAPI.userChannelError {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                        .padding(.horizontal, 8)
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 12)
            Spacer()  // EN: Push content to top. TR: İçeriği üste it.
        }
        .padding(.top, 36)  // EN: Extra top padding. TR: Fazladan üst boşluk.
        .padding(.leading, 4)  // EN: Tiny leading padding. TR: Az bir sol boşluk.
        .frame(width: 160)  // EN: Fixed width. TR: Sabit genişlik.
        .background(
            VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
        )
        .overlay(
            Rectangle()
                .fill(Color.black.opacity(0.4))
                .frame(width: 0.3),
            alignment: .trailing
        )
    }
}
