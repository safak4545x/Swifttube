/*
 File Overview (EN)
 Purpose: Legacy/custom sidebar navigation component listing core pages and user subscriptions.
 Key Responsibilities:
 - Display navigation items with icons and selection state
 - List user subscriptions and allow channel selection
 Used By: Older navigation layouts; superseded by native macOS sidebar in MainContentView.

 Dosya Özeti (TR)
 Amacı: Çekirdek sayfalar ve kullanıcı aboneliklerini listeleyen eski/özel yan menü bileşeni.
 Ana Sorumluluklar:
 - Simge ve seçim durumu ile navigation öğelerini göstermek
 - Kullanıcı aboneliklerini listelemek ve kanal seçimini sağlamak
 Nerede Kullanılır: Eski navigasyon düzenlerinde; MainContentView’deki yerel sidebar ile yer değiştirmiştir.
*/

import SwiftUI

struct SidebarView: View {
        @EnvironmentObject var i18n: Localizer
    @Binding var selectedSidebarId: String
    @Binding var currentURL: String
    @Binding var showUserChannelInput: Bool
    @ObservedObject var youtubeAPI: YouTubeAPIService
    
    // Lokalize edilmiş dinamik sidebar öğeleri (global sabit yerine)
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
            // Sidebar yazıları sadece üstte
            ForEach(localizedSidebarItems) { item in
                Button(action: {
                    selectedSidebarId = item.id
                    currentURL = item.url
                    // Shorts sayfasına geçildiğinde Shorts videolarını yükle
                    if item.url == "https://www.youtube.com/shorts" {
                        youtubeAPI.fetchShortsVideos(suppressOverlay: false)
                    } else {
                        // Ana sayfa: seçili özel kategori varsa onu; yoksa Home önerileri
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
                        Spacer()  // Yazıları sola yaslamak için
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Abonelikler bölümü
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
                
                // Yükleme durumu
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
                
                // Kullanıcının kendi kanalı (URL'den alınan)
                if youtubeAPI.userChannelFromURL != nil {
                    VStack(alignment: .leading, spacing: 4) {
                        // URL'den alınan abonelikler
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
                        
                        // Daha fazla abonelik varsa göster
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
                
                if let error = youtubeAPI.userChannelError {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                        .padding(.horizontal, 8)
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 12)
            Spacer()  // Yazıları üste itmek için
        }
        .padding(.top, 36)  // Daha fazla üst padding
        .padding(.leading, 4)  // Çok az sol padding, yazıları tam sola al
        .frame(width: 160)  // Sabit genişlik
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
