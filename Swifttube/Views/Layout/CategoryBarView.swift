/*
 Overview / Genel Bakış
 EN: Top category bar on Home, listing custom categories, with scroll controls and an editor sheet.
 TR: Ana sayfada üst kategori çubuğu; özel kategorileri listeler, kaydırma kontrolleri ve düzenleyici içerir.
*/

// EN: SwiftUI for UI components. TR: UI bileşenleri için SwiftUI.
import SwiftUI

// EN: Horizontal chips for Home and custom categories with scrolling and editing. TR: Home ve özel kategoriler için yatay çipler, kaydırma ve düzenleme.
struct CategoryBarView: View {
    // EN: Localization helper for UI strings. TR: Arayüz metinleri için yerelleştirme yardımcısı.
    @EnvironmentObject var i18n: Localizer
    // EN: API facade exposing categories and fetch methods. TR: Kategorileri ve fetch metodlarını sunan API katmanı.
    @ObservedObject var youtubeAPI: YouTubeAPIService
    // EN: Current sidebar selection (affects visibility/active state). TR: Geçerli yan menü seçimi (görünürlüğü/aktifi etkiler).
    let selectedSidebarId: String

    // EN: Current scroll anchor index (Home=0, customs=1..N). TR: Geçerli kaydırma çıpası indeksi (Home=0, özel=1..N).
    @State private var scrollPosition: Int = 0
    // EN: Whether to show left/right scroll buttons. TR: Sol/sağ kaydırma düğmeleri görünsün mü.
    @State private var showScrollButtons: Bool = false
    // EN: Visible scroll view width tracker. TR: Görünür kaydırma alanı genişliği takibi.
    @State private var scrollViewWidth: CGFloat = 0
    // EN: Total content width tracker. TR: Toplam içerik genişliği takibi.
    @State private var contentWidth: CGFloat = 0
    // EN: Hovering state for left overlay button. TR: Sol örtü düğmesi hover durumu.
    @State private var isHoveringLeftArea: Bool = false
    // EN: Hovering state for right overlay button. TR: Sağ örtü düğmesi hover durumu.
    @State private var isHoveringRightArea: Bool = false
    // EN: Controls visibility of category editor sheet. TR: Kategori düzenleyici sayfasının görünürlüğü.
    @State private var showEditor: Bool = false
    // EN: Working copy for create/edit category. TR: Oluştur/düzenle için çalışma kopyası.
    @State private var draft: CustomCategory = CustomCategory(name: "", primaryKeyword: "")

    var body: some View {
        // EN: Hide on pages where categories are irrelevant. TR: Kategorilerin gereksiz olduğu sayfalarda gizle.
        Group {
            if shouldHideCategory {
                Color.clear.frame(height: 0).opacity(0)
            } else {
                ZStack(alignment: .center) {
                    // EN: Titlebar-like material + bottom hairline. TR: Başlık benzeri materyal + alt çizgi.
                    VisualEffectView(material: .titlebar, blendingMode: .withinWindow)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(Color(NSColor.separatorColor).opacity(0.18))
                                .frame(height: 0.5)
                        }

                    // EN: Horizontal scroll of Home + custom categories. TR: Home + özel kategoriler için yatay kaydırma.
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                // EN: Home chip triggers recommended feed. TR: Home çipi önerilen akışı tetikler.
                                Button(action: {
                                    // EN: Ask API to build home recommendations. TR: API'den ana sayfa önerileri iste.
                                    youtubeAPI.fetchHomeRecommendations()
                                    youtubeAPI.selectedCustomCategoryId = nil
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "house")
                                            .font(.system(size: 11))
                                        Text(i18n.t(.home))
                                            .font(.system(size: 11, weight: .medium))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 5)
                                    .background(
                                        youtubeAPI.selectedCustomCategoryId == nil && selectedSidebarId == "https://www.youtube.com/" && !youtubeAPI.isShowingSearchResults
                                            ? Color.accentColor.opacity(0.22)
                                            : Color.secondary.opacity(0.12)
                                    )
                                    .foregroundColor(
                                        youtubeAPI.selectedCustomCategoryId == nil && selectedSidebarId == "https://www.youtube.com/" && !youtubeAPI.isShowingSearchResults
                                            ? Color.accentColor
                                            : .primary
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.secondary.opacity(0.25), lineWidth: 0.6)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                                .id(0)

                                // EN: User-defined category chips. TR: Kullanıcı tanımlı kategori çipleri.
                                ForEach(Array(youtubeAPI.customCategories.enumerated()), id: \ .element.id) { index, custom in
                                    let isActive = youtubeAPI.selectedCustomCategoryId == custom.id
                                    Button(action: {
                                        // EN: Fetch videos for selected custom category. TR: Seçilen özel kategori için videoları çek.
                                        youtubeAPI.fetchVideos(for: custom)
                                    }) {
                                        HStack(spacing: 6) {
                                            Text(custom.name)
                                                .font(.system(size: 11, weight: .medium))
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 5)
                                        .background(
                                            isActive
                                                ? (Color.fromNamed(custom.colorName) ?? Color.blue).opacity(0.22)
                                                : Color.secondary.opacity(0.12)
                                        )
                                        .foregroundColor(
                                            isActive
                                                ? (Color.fromNamed(custom.colorName) ?? Color.blue)
                                                : .primary
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(Color.secondary.opacity(0.25), lineWidth: 0.6)
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        // EN: Delete selected category. TR: Seçilen kategoriyi sil.
                                        Button(role: .destructive) {
                                            if let i = youtubeAPI.customCategories.firstIndex(of: custom) {
                                                youtubeAPI.customCategories.remove(at: i)
                                            }
                                        } label: {
                                            Label(i18n.t(.delete), systemImage: "trash")
                                        }
                                        // EN: Open editor with current values. TR: Mevcut değerlerle düzenleyiciyi aç.
                                        Button {
                                            draft = custom
                                            showEditor = true
                                        } label: {
                                            Label(i18n.t(.customCategoryEdit), systemImage: "pencil")
                                        }
                                    }
                                    .id(index + 1)
                                }

                                // EN: New custom category. TR: Yeni özel kategori.
                                Button(action: {
                                    draft = CustomCategory(name: "", primaryKeyword: "")
                                    showEditor = true
                                }) {
                                    Image(systemName: "plus.circle")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.secondary)
                                        .frame(width: 22, height: 22)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8)
                            // EN: Measure content width to decide showing scroll buttons. TR: Kaydırma düğmelerini belirlemek için içerik genişliğini ölç.
                            .background(GeometryReader { geometry in
                                Color.clear
                                    .onAppear { updateContentWidth(geometry.size.width) }
                                    .onChange(of: geometry.size.width) { _, newWidth in
                                        updateContentWidth(newWidth)
                                    }
                            })
                        }
                        // EN: Measure visible scroll area width. TR: Görünür kaydırma alanı genişliğini ölç.
                        .background(GeometryReader { geometry in
                            Color.clear
                                .onAppear { updateScrollViewWidth(geometry.size.width, proxy: proxy) }
                                .onChange(of: geometry.size.width) { _, newWidth in
                                    updateScrollViewWidth(newWidth, proxy: proxy)
                                }
                        })
                        .onChange(of: scrollPosition) { _, newPosition in
                            withAnimation(.easeInOut(duration: 0.25)) {
                                proxy.scrollTo(newPosition, anchor: .center)
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                updateScrollButtonVisibility()
                            }
                        }
                        .onChange(of: youtubeAPI.selectedCustomCategoryId) { _, _ in
                            // EN: Keep current position; may recentre later. TR: Mevcut konumu koru; gerekirse ortalanır.
                        }

                        // EN: Left scroll overlay button. TR: Sol kaydırma örtü düğmesi.
                        .overlay(alignment: .leading) {
                            if showScrollButtons && scrollPosition > 0 {
                                HStack(spacing: 0) {
                                    Button(action: { scrollLeft() }) {
                                        Image(systemName: "chevron.left")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.secondary)
                                            .frame(width: 24, height: 24)
                                            .background(.ultraThinMaterial)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 0.6)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .opacity(isHoveringLeftArea ? 1 : 0)
                                    .animation(.easeInOut(duration: 0.15), value: isHoveringLeftArea)

                                    Spacer(minLength: 0)
                                }
                                .frame(width: 50)
                                .padding(.leading, 8)
                                .onHover { hovering in
                                    if showScrollButtons && scrollPosition > 0 { isHoveringLeftArea = hovering }
                                }
                            }
                        }
                        // EN: Right scroll overlay button. TR: Sağ kaydırma örtü düğmesi.
                        .overlay(alignment: .trailing) {
                            if showScrollButtons {
                                HStack(spacing: 0) {
                                    Spacer(minLength: 0)
                                    Button(action: { scrollRight() }) {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.secondary)
                                            .frame(width: 24, height: 24)
                                            .background(.ultraThinMaterial)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 0.6)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .opacity(isHoveringRightArea ? 1 : 0)
                                    .animation(.easeInOut(duration: 0.15), value: isHoveringRightArea)
                                }
                                .frame(width: 50)
                                .padding(.trailing, 8)
                                .onHover { hovering in
                                    // EN: Total scrollable = Home(0) + customs(1..N). TR: Toplam kaydırılabilir = Home(0) + özel(1..N).
                                    let lastIndex = max(0, youtubeAPI.customCategories.count)
                                    if showScrollButtons && scrollPosition < lastIndex { isHoveringRightArea = hovering }
                                }
                            }
                        }
                    }
                }
                .frame(height: 32)
                .zIndex(1)
                .sheet(isPresented: $showEditor) {
                    // EN: Modal editor to create/edit a custom category. TR: Özel kategori oluştur/düzenle için modal editör.
                    editorView
                }
            }
        }
    }

    // EN: Scroll left by a fixed number of items. TR: Sabit sayıda öğe sola kaydır.
    private func scrollLeft() {
        let newPosition = max(0, scrollPosition - 3)
        scrollPosition = newPosition
    }

    // EN: Scroll right by a fixed number of items. TR: Sabit sayıda öğe sağa kaydır.
    private func scrollRight() { scrollPosition = scrollPosition + 3 }

    // EN: Show scroll buttons only when content overflows. TR: İçerik taşınca kaydırma düğmelerini göster.
    private func updateScrollButtonVisibility() {
        showScrollButtons = contentWidth > scrollViewWidth
    }

    // EN: Simplified width updates; recompute button visibility. TR: Genişlik güncellemesini sadeleştir; düğme görünürlüğünü hesapla.
    private func updateContentWidth(_ newWidth: CGFloat) {
        contentWidth = newWidth
        updateScrollButtonVisibility()
    }

    // EN: Track visible width and center active chip after slight delay. TR: Görünür genişliği takip et ve kısa gecikmeyle aktif çipi ortala.
    private func updateScrollViewWidth(_ newWidth: CGFloat, proxy: ScrollViewProxy) {
        scrollViewWidth = newWidth
        updateScrollButtonVisibility()
        // EN: Slight delay to allow layout completion. TR: Yerleşimin tamamlanması için kısa gecikme.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            scrollToSelectedCategory(proxy: proxy)
        }
    }

    // EN: Scroll to selected custom category (or Home). TR: Seçili özel kategoriye (veya Home'a) kaydır.
    private func scrollToSelectedCategory(proxy: ScrollViewProxy) {
        // EN: Home id=0; custom chips start at 1. TR: Home id=0; özel çipler 1'den başlar.
        let targetIndex: Int = {
            if let selId = youtubeAPI.selectedCustomCategoryId,
               let idx = youtubeAPI.customCategories.firstIndex(where: { $0.id == selId }) {
                return idx + 1
            }
            return 0 // Home
        }()
        withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(targetIndex, anchor: .center) }
        scrollPosition = targetIndex
    }

    // EN: Hide category bar for feeds where it doesn't apply. TR: Uygulanmayan akışlarda kategori barını gizle.
    private var shouldHideCategory: Bool {
        selectedSidebarId == "https://www.youtube.com/feed/subscriptions" ||
        selectedSidebarId == "https://www.youtube.com/shorts" ||
        selectedSidebarId == "https://www.youtube.com/feed/history"
    }

    // MARK: - Editor Sheet
    // EN: Category editor UI with validation and color options. TR: Doğrulama ve renk seçenekleri olan kategori düzenleyici UI.
    private var editorView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(i18n.t(.customCategoryNewTitle))
                .font(.headline)
            HStack(spacing: 8) {
                // EN: Emoji prefix picker. TR: Emoji önek seçici.
                Menu {
                    let choices = ["🔥","⭐️","🎯","🎵","🎮","⚽️","📈","🎬","📰","🧪","🧠","📚","🍿","🚀","💡"]
                    ForEach(choices, id: \.self) { e in
                        Button(e) { draft.name = draft.name.hasPrefix(e + " ") ? draft.name : e + " " + draft.name }
                    }
                } label: {
                    Text("😀")
                        .font(.system(size: 14))
                        .frame(width: 28, height: 24)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize() // EN: Menu sizes to content. TR: Menü içerik kadar yer kaplar.
                .help(i18n.t(.customCategoryEmoji))
                // EN: Category name input. TR: Kategori adı girişi.
                TextField(i18n.t(.customCategoryName), text: $draft.name)
                    .frame(maxWidth: .infinity) // EN: Fill remaining width. TR: Kalan genişliği doldur.
            }
            // EN: Primary keyword (single word) required. TR: Birincil anahtar (tek kelime) zorunlu.
            TextField(i18n.t(.customCategoryPrimary), text: $draft.primaryKeyword)
            // EN: Validation feedback for multi-word primary. TR: Çok kelimeli birincil için uyarı.
            if draft.primaryKeyword.trimmingCharacters(in: .whitespacesAndNewlines).contains(where: { $0.isWhitespace }) {
                Text(i18n.t(.customCategoryPrimarySingleWord))
                    .font(.caption)
                    .foregroundColor(.red)
            }
            // EN: Optional secondary keyword. TR: Opsiyonel ikincil anahtar.
            TextField(i18n.t(.customCategorySecondary), text: Binding(
                get: { draft.secondaryKeyword ?? "" },
                set: { draft.secondaryKeyword = $0.isEmpty ? nil : $0 }
            ))
            HStack {
                // EN: Optional third/fourth keywords. TR: Opsiyonel üçüncü/dördüncü anahtarlar.
                TextField(i18n.t(.customCategoryThird), text: Binding(
                    get: { draft.thirdKeyword ?? "" },
                    set: { draft.thirdKeyword = $0.isEmpty ? nil : $0 }
                ))
                TextField(i18n.t(.customCategoryFourth), text: Binding(
                    get: { draft.fourthKeyword ?? "" },
                    set: { draft.fourthKeyword = $0.isEmpty ? nil : $0 }
                ))
            }
            HStack {
                // EN: Date filter for query building. TR: Sorgu oluşturma için tarih filtresi.
                Picker(i18n.t(.date), selection: $draft.dateFilter) {
                    ForEach(CustomDateFilter.allCases) { d in
                        Text(i18n.t(d.localizationKey)).tag(d)
                    }
                }
            }
            HStack {
                Text(i18n.t(.customCategoryColor))
                let colors = ["blue","green","red","orange","purple","pink","teal","yellow","brown"]
                // EN: Optional color selection mapped to Localizer keys. TR: Localizer anahtarlarına eşlenen opsiyonel renk seçimi.
                Picker(i18n.t(.customCategoryColor), selection: Binding(
                    get: { draft.colorName ?? "" },
                    set: { draft.colorName = $0.isEmpty ? nil : $0 }
                )) {
                    Text(i18n.t(.customCategoryDefaultColor)).tag("")
                    ForEach(colors, id: \.self) { name in
                        let key: Localizer.Key = {
                            switch name {
                            case "blue": return .customColorBlue
                            case "green": return .customColorGreen
                            case "red": return .customColorRed
                            case "orange": return .customColorOrange
                            case "purple": return .customColorPurple
                            case "pink": return .customColorPink
                            case "teal": return .customColorTeal
                            case "yellow": return .customColorYellow
                            case "brown": return .customColorBrown
                            default: return .customColorBlue
                            }
                        }()
                        Text(i18n.t(key)).tag(name)
                    }
                }.labelsHidden()
            }
            HStack {
                // EN: Reset draft to defaults. TR: Taslağı varsayılanlara sıfırla.
                Button(i18n.t(.reset)) {
                    draft = CustomCategory(name: "", primaryKeyword: "")
                }
                Spacer()
                // EN: Validate then save and fetch videos. TR: Doğrula, kaydet ve videoları çek.
                Button(i18n.t(.customCategoryConfirm)) {
                    // EN: Basic validation for name and single-word primary. TR: Ad ve tek kelimelik birincil için temel doğrulama.
                    let nameOK = !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    let primary = draft.primaryKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
                    let isSingleWord = !primary.isEmpty && !primary.contains(where: { $0.isWhitespace })
                    guard nameOK && isSingleWord else { return }
                    if let idx = youtubeAPI.customCategories.firstIndex(where: { $0.id == draft.id }) {
                        youtubeAPI.customCategories[idx] = draft
                    } else {
                        youtubeAPI.customCategories.append(draft)
                    }
                    showEditor = false
                    youtubeAPI.fetchVideos(for: draft)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    draft.primaryKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    draft.primaryKeyword.trimmingCharacters(in: .whitespacesAndNewlines).contains(where: { $0.isWhitespace })
                )
            }
            .padding(.top, 6)
        }
        .padding(16)
        .frame(width: 460)
    }
}

