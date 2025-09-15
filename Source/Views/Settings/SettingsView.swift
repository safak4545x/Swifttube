/*
 Overview / Genel Bakış
 EN: Settings window with tabs for General, Appearance, and About; manages API key, caches, preferences, and player UI.
 TR: Genel, Görünüm ve Hakkında sekmelerinden oluşan ayarlar; API anahtarı, önbellek, tercihler ve oynatıcı arayüzünü yönetir.
*/

import SwiftUI

// EN: Root settings view with macOS TabView. TR: macOS TabView kullanan kök ayarlar görünümü.
struct SettingsView: View {
    #if os(macOS)
    private enum Tabs: Hashable {
        case general, appearance, about
    }
    
    @State private var selection: Tabs = .general
    #endif
    
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var i18n: Localizer
    
    var body: some View {
        settings
    }
    
    var settings: some View {
        #if os(macOS)
        TabView(selection: $selection) {
            // EN: App behavior, language, cache, and API key. TR: Uygulama davranışı, dil, önbellek ve API anahtarı.
            GeneralSettings()
                .padding(.leading, 20)
                .tabItem { Label(i18n.t(.generalTab), systemImage: "gear") }
                .tag(Tabs.general)

            // EN: Player UI visibility toggles. TR: Oynatıcı arayüzü görünürlük anahtarları.
            PlayerSettings()
                .padding(.leading, 20)
                .tabItem { Label(i18n.t(.appearanceTab), systemImage: "play.rectangle") }
                .tag(Tabs.appearance)

            // EN: Static app info. TR: Statik uygulama bilgisi.
            AboutSettings()
                .padding(.leading, 20)
                .tabItem { Label(i18n.t(.aboutTab), systemImage: "info.circle") }
                .tag(Tabs.about)
        }
        .frame(width: 660, height: windowHeight)
        #endif
    }
    
    #if os(macOS)
    // EN: Keep uniform window height per tab. TR: Her sekme için tekdüze pencere yüksekliği.
    private var windowHeight: Double {
        switch selection {
        case .general:
            return 600
    case .appearance:
            return 600
        case .about:
            return 600
        }
    }
    #endif
}

// EN: General app settings (region/language/cache/API key). TR: Genel ayarlar (bölge/dil/önbellek/API anahtarı).
struct GeneralSettings: View {
    @EnvironmentObject var api: YouTubeAPIService
    @EnvironmentObject private var i18n: Localizer
    @EnvironmentObject private var tabs: TabCoordinator
    @State private var tempKey: String = ""
    @State private var showSaved: Bool = false
    @State private var showConfirmClearAll = false
    @State private var showConfirmClearImages = false
    @State private var showConfirmClearData = false
    @FocusState private var keyFieldFocused: Bool
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.en.rawValue
    // Remember tabs preference
    @AppStorage("preferences:rememberTabsEnabled") private var rememberTabsEnabled: Bool = false
    private var selectedLanguage: Binding<AppLanguage> {
        Binding<AppLanguage>(
            get: { AppLanguage(rawValue: appLanguageRaw) ?? .en },
            set: { appLanguageRaw = $0.rawValue }
        )
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // EN: Region picker affects feed localization. TR: Bölge seçimi akış yerelleştirmesini etkiler.
                GroupBox(label: Label(i18n.t(.algorithmTabTitle), systemImage: "slider.horizontal.3")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(i18n.t(.algorithmLocationDesc))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        HStack(spacing: 12) {
                            // Left-click popup style selector (Picker)
                            let appLang = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.en.rawValue) ?? .en
                            Picker("", selection: $api.selectedRegion) {
                                // GLOBAL option
                                Text("🌐 Global").tag("GLOBAL")
                                ForEach(YouTubeRegions.supported.filter { $0 != "GLOBAL" }, id: \.self) { code in
                                    Text("\(YouTubeRegions.flag(for: code)) \(YouTubeRegions.localizedName(for: code, appLanguage: appLang))").tag(code)
                                }
                            }
                            .pickerStyle(.menu)
                            .controlSize(.regular)
                            .labelsHidden()
                            Spacer()
                        }
                    }
                    .padding(12)
                }
                // EN: App language picker and hint. TR: Uygulama dili seçici ve not.
                GroupBox(label: Label(i18n.t(.languageGroupTitle), systemImage: "globe")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(i18n.t(.languageAppLanguage))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Picker("Language", selection: selectedLanguage) {
                            ForEach(AppLanguage.allCases) { lang in
                                Text(lang.displayName).tag(lang)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text(i18n.t(.languageNote))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                }
                // EN: Cache management and remember-tabs toggle. TR: Önbellek yönetimi ve sekmeleri hatırla anahtarı.
                GroupBox(label: Label(i18n.t(.cacheTitle), systemImage: "internaldrive.fill")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(i18n.t(.cacheDesc))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        // Remember Tabs on Startup
                        Toggle(isOn: $rememberTabsEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(i18n.t(.rememberTabsTitle)).fontWeight(.semibold)
                                Text(i18n.t(.rememberTabsDesc)).font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .onChange(of: rememberTabsEnabled) { _, newVal in
                            if newVal { tabs.saveSessionIfEnabled() }
                        }
                        HStack(spacing: 10) {
                            Button(role: .destructive) { showConfirmClearImages = true } label: {
                                Label(i18n.t(.clearImageCache), systemImage: "trash")
                            }
                            Button(role: .destructive) { showConfirmClearData = true } label: {
                                Label(i18n.t(.clearDataCache), systemImage: "trash")
                            }
                            Spacer()
                            Button(role: .destructive) { showConfirmClearAll = true } label: {
                                Label(i18n.t(.clearAllData), systemImage: "trash.circle")
                            }
                            .keyboardShortcut(.delete, modifiers: [.command, .shift])
                        }
                    }
                    .padding(12)
                    .alert(i18n.t(.confirmClearImageTitle), isPresented: $showConfirmClearImages) {
                        Button(i18n.t(.delete), role: .destructive) { api.clearImageCache() }
                        Button(i18n.t(.cancel), role: .cancel) { }
                    } message: {
                        Text(i18n.t(.confirmClearImageMessage))
                    }
                    .alert(i18n.t(.confirmClearDataTitle), isPresented: $showConfirmClearData) {
                        Button(i18n.t(.delete), role: .destructive) { api.clearDataCache() }
                        Button(i18n.t(.cancel), role: .cancel) { }
                    } message: {
                        Text(i18n.t(.confirmClearDataMessage))
                    }
                    .alert(i18n.t(.confirmClearAllTitle), isPresented: $showConfirmClearAll) {
                        Button(i18n.t(.delete), role: .destructive) { api.clearAllData() }
                        Button(i18n.t(.cancel), role: .cancel) { }
                    } message: {
                        Text(i18n.t(.confirmClearAllMessage))
                    }
                }
                // EN: API key entry, save/clear/paste actions, and status. TR: API anahtarı girişi, kaydet/temizle/yapıştır eylemleri ve durum.
                GroupBox(label: Label(i18n.t(.apiKeyTitle), systemImage: "key.fill")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(i18n.t(.apiKeyDesc))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        VStack(spacing: 10) {
                            HStack(alignment: .center, spacing: 10) {
                                TextField("API Key", text: $tempKey, prompt: Text("AIza..."))
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .font(.system(.body, design: .monospaced))
                                    .disableAutocorrection(true)
                                    .focused($keyFieldFocused)
                                Button(action: saveKey) { Label(i18n.t(.save), systemImage: "tray.and.arrow.down") }
                                    .buttonStyle(.borderedProminent)
                                    .keyboardShortcut(.return, modifiers: [])
                            }
                            .animation(.easeInOut(duration: 0.15), value: showSaved)
                            statusLine
                        }
                        HStack(spacing: 12) {
                            Image(systemName: api.apiKey.isEmpty ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                                .foregroundColor(api.apiKey.isEmpty ? .orange : .green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(api.apiKey.isEmpty ? i18n.t(.statusNoAPIKey) : i18n.t(.statusAPIKeyActive))
                                    .font(.caption).fontWeight(.semibold)
                                Text(api.apiKey.isEmpty ? i18n.t(.statusNoAPIKeyDesc) : "\(i18n.t(.statusAPIKeyActiveDesc)) \(api.apiKey.count) characters")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(api.apiKey.isEmpty ? i18n.t(.paste) : i18n.t(.clear)) {
                                if api.apiKey.isEmpty {
                                    if let paste = NSPasteboard.general.string(forType: .string) { tempKey = paste }
                                } else {
                                    api.apiKey = ""; tempKey = ""; showSaved = false
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.top, 2)
                        if showSaved { Text(i18n.t(.saved)).font(.caption).foregroundColor(.green).transition(.opacity) }
                    }
                    .padding(12)
                    .onAppear { tempKey = api.apiKey }
                }
            }
            // Keep only a left inset; no right/top/bottom to remove gaps
            .padding(.leading, 24)
            .padding(.trailing, 0)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func saveKey() {
        let newVal = tempKey.trimmingCharacters(in: .whitespacesAndNewlines)
        api.apiKey = newVal
        showSaved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { showSaved = false }
    }
    @ViewBuilder private var statusLine: some View {
        if api.apiKey.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "xmark.octagon.fill").foregroundColor(.red)
                Text("\(i18n.t(.statusNoAPIKey)) – \(i18n.t(.statusNoAPIKeyDesc))").font(.caption).foregroundColor(.red)
            }
            .transition(.opacity)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                Text("\(i18n.t(.statusAPIKeyActive)). \(i18n.t(.statusAPIKeyActiveDesc)) \(api.apiKey.count)").font(.caption).foregroundColor(.green)
            }
            .transition(.opacity)
        }
    }
}

// EN: Player/Appearance toggles for embedded YouTube UI elements. TR: Gömülü YouTube arayüz öğeleri için Oynatıcı/Görünüm anahtarları.
struct PlayerSettings: View {
    @StateObject private var settings = PlayerAppearanceSettings()
    @EnvironmentObject private var i18n: Localizer
    var body: some View {
        VStack(spacing: 0) {
            // Scrollable content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
            GroupBox(label: Label(i18n.t(.appearanceTopSection), systemImage: "eye")) {
                        VStack(alignment: .leading, spacing: 6) {
                // EN: Hide elements overlaying the video. TR: Video üzerinde görünen öğeleri gizle.
                Text(i18n.t(.appearanceTopHelp))
                                .font(.footnote)
                                .foregroundColor(.secondary)
                Toggle(i18n.t(.appearanceTopChannelLogo), isOn: $settings.hideChannelAvatar)
                Toggle(i18n.t(.appearanceTopChannelName), isOn: $settings.hideChannelName)
                Toggle(i18n.t(.appearanceTopVideoTitle), isOn: $settings.hideVideoTitle)
                Toggle(i18n.t(.appearanceTopMoreVideosBox), isOn: $settings.hideMoreVideosOverlay)
                Toggle(i18n.t(.appearanceTopContextMenu), isOn: $settings.hideContextMenu)
                Toggle(i18n.t(.appearanceTopWatchLater), isOn: $settings.hideWatchLater)
                Toggle(i18n.t(.appearanceTopShare), isOn: $settings.hideShare)
                        }
                        .padding(12)
                    }
            GroupBox(label: Label(i18n.t(.appearanceBottomSection), systemImage: "rectangle.on.rectangle")) {
                        VStack(alignment: .leading, spacing: 6) {
                // EN: Hide controls within the player chrome. TR: Oynatıcı çerçevesindeki kontrolleri gizle.
                Text(i18n.t(.appearanceBottomHelp))
                                .font(.footnote)
                                .foregroundColor(.secondary)
                Toggle(i18n.t(.appearanceBottomSubtitles), isOn: $settings.hideSubtitlesButton)
                Toggle(i18n.t(.appearanceBottomQuality), isOn: $settings.hideQualityButton)
                Toggle(i18n.t(.appearanceBottomYouTubeLogo), isOn: $settings.hideYouTubeLogo)
                Toggle(i18n.t(.appearanceBottomAirPlay), isOn: $settings.hideAirPlayButton)
                Toggle(i18n.t(.appearanceBottomChapterTitle), isOn: $settings.hideChapterTitle)
                Toggle(i18n.t(.appearanceBottomScrubPreview), isOn: $settings.hideScrubPreview)
                        }
                        .padding(12)
                    }
                }
                .padding(.leading, 24)
                .padding(.trailing, 0)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Bottom fixed panel
            VStack(spacing: 0) {
                Divider()
                HStack(alignment: .center, spacing: 12) {
                    Text(i18n.t(.restartHint))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    // EN: Relaunch app to apply appearance toggles globally. TR: Görünüm anahtarlarını uygulanması için uygulamayı yeniden başlat.
                    Button { NSApp.terminate(nil) } label: {
                        Label(i18n.t(.restartApp), systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                    // EN: Restore defaults for all toggles. TR: Tüm anahtarları varsayılanlara döndür.
                    Button(role: .destructive) { settings.reset() } label: {
                        Label(i18n.t(.reset), systemImage: "arrow.counterclockwise")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .padding(.leading, 24)
                .padding(.trailing, 16)
                #if os(macOS)
                .background(Color(nsColor: .underPageBackgroundColor))
                #endif
            }
        }
    }
}

// QuotaSettings tamamen kaldırıldı (API key sistemi söküldü)

struct AboutSettings: View {
    var body: some View {
        VStack {
            Text("About")
                .font(.title2)
                .padding()
            
            Text("Swifttube")
                .font(.headline)
            
            Text("Version 1.0.0")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            // Empty content
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(YouTubeAPIService())
            .frame(width: 600, height: 400)
    }
}
