/*
 Overview / Genel Bakış
 EN: macOS app entry point; wires core environment objects, configures URLCache, defines main window and Settings scene.
 TR: macOS uygulama giriş noktası; temel environment nesnelerini bağlar, URLCache ayarlar, ana pencere ve Ayarlar sahnesini tanımlar.
*/

import SwiftUI

// EN: App entry point macro for macOS. TR: macOS için uygulama giriş noktası.
@main
struct SwifttubeApp: App {
    // EN: Central YouTube data/service model. TR: YouTube verileri ve servislerinin merkezi modeli.
    @StateObject private var api = YouTubeAPIService()
    // EN: Tab coordination and session persistence. TR: Sekme koordinasyonu ve oturum kalıcılığı.
    @StateObject private var tabs = TabCoordinator()
    // EN: Localization provider for UI strings. TR: UI metinleri için yerelleştirme sağlayıcısı.
    @StateObject private var i18n = Localizer()
    init() {
        // EN: Configure shared URLCache for HTTP caching (revalidation, small responses).
        // TR: HTTP önbelleği (yeniden doğrulama, küçük yanıtlar) için ortak URLCache yapılandırması.
        let mem = 64 * 1024 * 1024      // EN: 64MB in-memory cache. TR: 64MB bellek önbelleği.
        let disk = 256 * 1024 * 1024    // EN: 256MB disk cache. TR: 256MB disk önbelleği.
        URLCache.shared = URLCache(memoryCapacity: mem, diskCapacity: disk, directory: nil)
    }
    var body: some Scene {
        WindowGroup {
            MainAppView()
                // EN: Inject shared environment objects into the view tree. TR: Ortak environment nesnelerini görünüm ağacına enjekte eder.
                .environmentObject(api)
                .environmentObject(tabs)
                .environmentObject(i18n)
                // EN: Restore previous session’s tabs on launch (if enabled). TR: Açılışta önceki sekmeleri geri yükler (açıksa).
                .onAppear { tabs.restoreSessionIfEnabled() }
                // EN: Save current session when the app is terminating. TR: Uygulama kapanırken mevcut oturumu kaydeder.
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    tabs.saveSessionIfEnabled()
                }
        }
        // EN: Use the standard title bar style. TR: Standart başlık çubuğu stilini kullan.
        .windowStyle(.titleBar)
        
        Settings {
            SettingsView()
                // EN: Inject same shared objects for Settings UI. TR: Ayarlar arayüzü için aynı ortak nesneleri enjekte et.
                .environmentObject(api)
                .environmentObject(tabs)
                .environmentObject(i18n)
        }
    }
}
