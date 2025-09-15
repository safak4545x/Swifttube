
/*
 File Overview (EN)
 Purpose: Reusable header area for sections/pages, hosting titles, actions, and optional controls consistent with the app's design.
 Key Responsibilities:
 - Present section/page titles and contextual action buttons
 - Keep spacing and visual style consistent across views
 Used By: Various pages requiring a styled header.

 Dosya Özeti (TR)
 Amacı: Sayfa/bölüm başlıkları, eylemler ve opsiyonel kontroller için yeniden kullanılabilir üst bölge bileşeni.
 Ana Sorumluluklar:
 - Başlık ve bağlamsal eylem butonlarını sunmak
 - Görsel stil ve boşlukları farklı görünümler arasında tutarlı kılmak
 Nerede Kullanılır: Başlık alanına ihtiyaç duyan sayfalarda.
*/

import SwiftUI

struct HeaderView: View {
    @Binding var searchText: String
    @FocusState var isSearchFocused: Bool
    @Binding var showChannelSearch: Bool
    @Binding var showPlaylistSearch: Bool
    @ObservedObject var youtubeAPI: YouTubeAPIService
    @EnvironmentObject private var i18n: Localizer
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.en.rawValue
    private var appLanguage: AppLanguage { AppLanguage(rawValue: appLanguageRaw) ?? .en }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                // App icon ve başlık (Swifttube)
                HStack(spacing: 6) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 22, height: 22)
                        .cornerRadius(4)
                    Text("Swifttube")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                // Arama ve Butonlar Bölümü
                HStack(spacing: 12) {
                    // Arama Çubuğu
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.textBackgroundColor).opacity(0.8))
                        .frame(width: 200, height: 24)
                        .overlay(
                            HStack {
                                Button(action: {
                                    // Search functionality
                                    if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        youtubeAPI.searchVideos(query: searchText)
                                    }
                                    isSearchFocused = false
                                }) {
                                    Image(systemName: "magnifyingglass")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 12))
                                }
                                .buttonStyle(.plain)
                                
                                TextField(
                                    i18n.t(.searchPlaceholder), text: $searchText,
                                    onCommit: {
                                        // Search functionality
                                        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                            youtubeAPI.searchVideos(query: searchText)
                                        }
                                        isSearchFocused = false
                                    }
                                )
                                .focused($isSearchFocused)
                                .foregroundColor(.primary)
                                .font(.system(size: 12))
                                .textFieldStyle(PlainTextFieldStyle())
                                // Incremental search kaldırıldı: sadece Enter (onCommit) veya ikon butonu ile sonuç getirilecek.
                                .onReceive(
                                    NotificationCenter.default.publisher(
                                        for: NSApplication.didBecomeActiveNotification)
                                ) { _ in
                                    // Uygulama aktif olduğunda fokus olmasını engelle
                                    isSearchFocused = false
                                }
                                .onReceive(
                                    NotificationCenter.default.publisher(
                                        for: NSWindow.didBecomeKeyNotification)
                                ) { _ in
                                    // Pencere aktif olduğunda fokus olmasını engelle
                                    isSearchFocused = false
                                }
                                .onAppear {
                                    // Uygulama açıldığında fokus olmasını engelle
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        isSearchFocused = false
                                    }
                                }
                                .onAppear {
                                    // Uygulama açıldığında fokus olmasını engelle
                                    isSearchFocused = false
                                }
                                .onTapGesture {
                                    // Sadece mouse ile tıklandığında fokus ol
                                    isSearchFocused = true
                                }
                            }
                            .padding(.horizontal, 6)
                        )
                        .onTapGesture {
                            // Arama çubuğu alanına tıklandığında fokus ol
                            isSearchFocused = true
                        }
                    
                    // Dil seçimi ve arama butonları
                    HStack(spacing: 8) {
                        Menu {
                            Picker("Language", selection: Binding(
                                get: { AppLanguage(rawValue: appLanguageRaw) ?? .en },
                                set: { appLanguageRaw = $0.rawValue }
                            )) {
                                ForEach(AppLanguage.allCases) { lang in
                                    Text(lang.displayName).tag(lang)
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "globe")
                                    .font(.system(size: 14))
                                Text(appLanguage.displayName)
                                    .font(.caption)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.15))
                            .foregroundColor(.primary)
                            .cornerRadius(6)
                        }
                        .menuStyle(.borderlessButton)

                        Button(action: {
                            showChannelSearch = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "person.2")
                                    .font(.system(size: 14))
                                Text(i18n.t(.channels))
                                    .font(.caption)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.15))
                            .foregroundColor(.blue)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            showPlaylistSearch = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "list.bullet")
                                    .font(.system(size: 14))
                                Text(i18n.t(.playlists))
                                    .font(.caption)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.15))
                            .foregroundColor(.green)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)  // Küçük üst padding
        .frame(height: 44)  // Biraz daha yüksek
        .background(.ultraThickMaterial)
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(.separatorColor).opacity(0.2)),
            alignment: .bottom
        )
    }
}
