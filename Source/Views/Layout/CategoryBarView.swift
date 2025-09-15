/*
 File Overview (EN)
 Purpose: Top category bar on Home page for selecting custom categories and triggering content refresh.
 Key Responsibilities:
 - Display available custom categories and highlight the active one
 - Notify YouTubeAPIService to fetch videos for the selected category
 - Present a compact, sticky header-like UI
 Used By: MainContentView (Home page).

 Dosya Özeti (TR)
 Amacı: Ana sayfadaki üst kategori barı; özel kategorileri seçmek ve içeriği yenilemek için kullanılır.
 Ana Sorumluluklar:
 - Mevcut özel kategorileri göstermek ve aktif olanı vurgulamak
 - Seçime göre YouTubeAPIService'e video çekimi tetiklemek
 - Kompakt, sabit başlık benzeri bir UI sunmak
 Nerede Kullanılır: MainContentView (Ana sayfa).
*/

import SwiftUI

struct CategoryBarView: View {
    @EnvironmentObject var i18n: Localizer
    @ObservedObject var youtubeAPI: YouTubeAPIService
    let selectedSidebarId: String

    @State private var scrollPosition: Int = 0
    @State private var showScrollButtons: Bool = false
    @State private var scrollViewWidth: CGFloat = 0
    @State private var contentWidth: CGFloat = 0
    @State private var isHoveringLeftArea: Bool = false
    @State private var isHoveringRightArea: Bool = false
    @State private var showEditor: Bool = false
    @State private var draft: CustomCategory = CustomCategory(name: "", primaryKeyword: "")

    var body: some View {
        Group {
            if shouldHideCategory {
                Color.clear.frame(height: 0).opacity(0)
            } else {
                ZStack(alignment: .center) {
                    // Titlebar benzeri materyal ve in-window blur
                    VisualEffectView(material: .titlebar, blendingMode: .withinWindow)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(Color(NSColor.separatorColor).opacity(0.18))
                                .frame(height: 0.5)
                        }

                    // Kategoriler scroll view'i (Home + Custom categories)
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                // Home static button
                                Button(action: {
                                    // Home: analyze watch history and recommend similar videos
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

                                // User custom categories
                                ForEach(Array(youtubeAPI.customCategories.enumerated()), id: \ .element.id) { index, custom in
                                    let isActive = youtubeAPI.selectedCustomCategoryId == custom.id
                                    Button(action: {
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
                                        Button(role: .destructive) {
                                            if let i = youtubeAPI.customCategories.firstIndex(of: custom) {
                                                youtubeAPI.customCategories.remove(at: i)
                                            }
                                        } label: {
                                            Label(i18n.t(.delete), systemImage: "trash")
                                        }
                                        Button {
                                            draft = custom
                                            showEditor = true
                                        } label: {
                                            Label(i18n.t(.customCategoryEdit), systemImage: "pencil")
                                        }
                                    }
                                    .id(index + 1)
                                }

                                // Plus button
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
                            // İçerik genişliğini ölç
                            .background(GeometryReader { geometry in
                                Color.clear
                                    .onAppear { updateContentWidth(geometry.size.width) }
                                    .onChange(of: geometry.size.width) { _, newWidth in
                                        updateContentWidth(newWidth)
                                    }
                            })
                        }
                        // ScrollView görünür genişliğini ölç
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
                            // keep current position; optionally center active button
                        }

                        // Scroll butonları
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
                                    // Total scrollable items: Home (0) + custom categories (1..N)
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
                    editorView
                }
            }
        }
    }

    private func scrollLeft() {
        let newPosition = max(0, scrollPosition - 3)
        scrollPosition = newPosition
    }

    private func scrollRight() { scrollPosition = scrollPosition + 3 }

    private func updateScrollButtonVisibility() {
        showScrollButtons = contentWidth > scrollViewWidth
    }

    // Tekrarlayan genişlik güncellemelerini sadeleştir
    private func updateContentWidth(_ newWidth: CGFloat) {
        contentWidth = newWidth
        updateScrollButtonVisibility()
    }

    private func updateScrollViewWidth(_ newWidth: CGFloat, proxy: ScrollViewProxy) {
        scrollViewWidth = newWidth
        updateScrollButtonVisibility()
        // Genişlik değişiminden kısa süre sonra aktif kategoriye merkezle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            scrollToSelectedCategory(proxy: proxy)
        }
    }

    private func scrollToSelectedCategory(proxy: ScrollViewProxy) {
        // Home has id 0, custom chips have ids starting from 1
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

    private var shouldHideCategory: Bool {
        selectedSidebarId == "https://www.youtube.com/feed/subscriptions" ||
        selectedSidebarId == "https://www.youtube.com/shorts" ||
        selectedSidebarId == "https://www.youtube.com/feed/history"
    }

    // MARK: - Editor Sheet
    private var editorView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(i18n.t(.customCategoryNewTitle))
                .font(.headline)
            HStack(spacing: 8) {
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
                .fixedSize() // Menü sadece içeriği kadar yer kaplasın
                .help(i18n.t(.customCategoryEmoji))
                TextField(i18n.t(.customCategoryName), text: $draft.name)
                    .frame(maxWidth: .infinity) // İsim alanı kalan genişliği doldursun
            }
            TextField(i18n.t(.customCategoryPrimary), text: $draft.primaryKeyword)
            // Validation: primary must be single word
            if draft.primaryKeyword.trimmingCharacters(in: .whitespacesAndNewlines).contains(where: { $0.isWhitespace }) {
                Text(i18n.t(.customCategoryPrimarySingleWord))
                    .font(.caption)
                    .foregroundColor(.red)
            }
            TextField(i18n.t(.customCategorySecondary), text: Binding(
                get: { draft.secondaryKeyword ?? "" },
                set: { draft.secondaryKeyword = $0.isEmpty ? nil : $0 }
            ))
            HStack {
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
                Picker(i18n.t(.date), selection: $draft.dateFilter) {
                    ForEach(CustomDateFilter.allCases) { d in
                        Text(i18n.t(d.localizationKey)).tag(d)
                    }
                }
            }
            HStack {
                Text(i18n.t(.customCategoryColor))
                let colors = ["blue","green","red","orange","purple","pink","teal","yellow","brown"]
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
                Button(i18n.t(.reset)) {
                    draft = CustomCategory(name: "", primaryKeyword: "")
                }
                Spacer()
                Button(i18n.t(.customCategoryConfirm)) {
                    // Basic validation
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

