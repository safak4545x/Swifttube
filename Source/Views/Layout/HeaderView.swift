/*
 Overview / Genel Bakış
 EN: Reusable page header with a search box, language picker, and quick channel/playlist search actions.
 TR: Arama kutusu, dil seçici ve hızlı kanal/oynatma listesi aramaları içeren tekrar kullanılabilir sayfa başlığı.
*/

// EN: SwiftUI for view composition. TR: Görünüm bileşimi için SwiftUI.
import SwiftUI

// EN: Compact header; embeds search and quick actions. TR: Kompakt başlık; arama ve hızlı eylemler içerir.
struct HeaderView: View {
    // EN: Two-way bound search text. TR: İki yönlü bağlı arama metni.
    @Binding var searchText: String
    // EN: Focus state to control TextField focus. TR: TextField odağını kontrol eden focus durumu.
    @FocusState var isSearchFocused: Bool
    // EN: Toggles for auxiliary search sheets. TR: Yardımcı arama sayfaları için anahtarlar.
    @Binding var showChannelSearch: Bool
    @Binding var showPlaylistSearch: Bool
    // EN: API service to perform searches. TR: Arama yapmak için API servisi.
    @ObservedObject var youtubeAPI: YouTubeAPIService
    // EN: Localizer for UI labels. TR: UI etiketleri için yerelleştirici.
    @EnvironmentObject private var i18n: Localizer
    // EN: Persisted app language (EN/TR). TR: Kalıcı uygulama dili (EN/TR).
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.en.rawValue
    private var appLanguage: AppLanguage { AppLanguage(rawValue: appLanguageRaw) ?? .en }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                // EN: App icon and title. TR: Uygulama simgesi ve başlık.
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
                
                // EN: Search bar and quick action buttons. TR: Arama çubuğu ve hızlı eylem butonları.
                HStack(spacing: 12) {
                    // EN: Search box with icon button and Enter commit. TR: İkon butonu ve Enter ile arama kutusu.
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.textBackgroundColor).opacity(0.8))
                        .frame(width: 200, height: 24)
                        .overlay(
                            HStack {
                                Button(action: {
                                    // EN: Trigger search if non-empty; blur focus. TR: Boş değilse aramayı tetikle; odağı kaldır.
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
                                        // EN: Trigger search on Enter. TR: Enter ile aramayı çalıştır.
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
                                // EN: Incremental search removed; only Enter or icon triggers. TR: Artımlı arama kaldırıldı; sadece Enter veya ikon tetikler.
                                .onReceive(
                                    NotificationCenter.default.publisher(
                                        for: NSApplication.didBecomeActiveNotification)
                                ) { _ in
                                    // EN: Avoid auto-focus when app becomes active. TR: Uygulama aktif olunca otomatik odaklanmayı engelle.
                                    isSearchFocused = false
                                }
                                .onReceive(
                                    NotificationCenter.default.publisher(
                                        for: NSWindow.didBecomeKeyNotification)
                                ) { _ in
                                    // EN: Avoid auto-focus when window becomes key. TR: Pencere aktif olunca otomatik odaklanmayı engelle.
                                    isSearchFocused = false
                                }
                                .onAppear {
                                    // EN: Avoid focus shortly after appear. TR: Göründükten kısa süre sonra odaklanmayı engelle.
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        isSearchFocused = false
                                    }
                                }
                                .onAppear {
                                    // EN: Double-guard: keep unfocused initially. TR: Çift koruma: başlangıçta odaksız tut.
                                    isSearchFocused = false
                                }
                                .onTapGesture {
                                    // EN: Focus only when user clicks. TR: Yalnızca kullanıcı tıklayınca odaklan.
                                    isSearchFocused = true
                                }
                            }
                            .padding(.horizontal, 6)
                        )
                        .onTapGesture {
                            // EN: Focus when tapping the search area. TR: Arama alanına tıklayınca odaklan.
                            isSearchFocused = true
                        }
                    
                    // EN: Language menu and channel/playlist quick searches. TR: Dil menüsü ve kanal/oynatma listesi hızlı aramaları.
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
                            // EN: Open channel search sheet. TR: Kanal arama sayfasını aç.
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
                            // EN: Open playlist search sheet. TR: Oynatma listesi arama sayfasını aç.
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
        .padding(.top, 8)  // EN: Slight top padding. TR: Küçük üst boşluk.
        .frame(height: 44)  // EN: Slightly taller header. TR: Biraz daha yüksek başlık.
        .background(.ultraThickMaterial) // EN: Blurred header background. TR: Blur'lu başlık arka planı.
        .overlay(
            Rectangle()
                .frame(height: 0.5) // EN: Hairline separator at bottom. TR: Altta ince ayırıcı çizgi.
                .foregroundColor(Color(.separatorColor).opacity(0.2)),
            alignment: .bottom
        )
    }
}
