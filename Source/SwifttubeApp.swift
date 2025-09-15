
/*
 File Overview (EN)
 Purpose: macOS app entry point. Creates and wires core environment objects (YouTubeAPIService, TabCoordinator, Localizer), configures a shared URL cache, and defines the main window and Settings scene.
 Key Responsibilities:
 - Initialize global services as @StateObject and inject via .environmentObject
 - Configure URLCache for better HTTP caching
 - Set up the main WindowGroup with MainAppView and session save/restore hooks
 - Provide a Settings window with SettingsView
 Used By: Entire application bootstrapping; hosts MainAppView.

 Dosya Özeti (TR)
 Amacı: macOS uygulamasının giriş noktası. Çekirdek ortam nesnelerini (YouTubeAPIService, TabCoordinator, Localizer) oluşturur/bağlar, ortak URL önbelleğini ayarlar ve ana pencere ile Ayarlar sahnesini tanımlar.
 Ana Sorumluluklar:
 - Global servisleri @StateObject olarak başlatıp .environmentObject ile enjekte etmek
 - HTTP önbelleklemesi için URLCache yapılandırmak
 - MainAppView içeren ana WindowGroup'u kurmak ve oturum kaydet/geri yükle kancalarını bağlamak
 - SettingsView ile Ayarlar penceresini sağlamak
 Nerede Kullanılır: Uygulama başlangıcı; MainAppView'i barındırır.
*/

import SwiftUI

@main
struct SwifttubeApp: App {
    @StateObject private var api = YouTubeAPIService()
    @StateObject private var tabs = TabCoordinator()
    @StateObject private var i18n = Localizer()
    init() {
        // Configure shared URLCache for HTTP-level caching (revalidation, small responses)
        let mem = 64 * 1024 * 1024
        let disk = 256 * 1024 * 1024
        URLCache.shared = URLCache(memoryCapacity: mem, diskCapacity: disk, directory: nil)
    }
    var body: some Scene {
        WindowGroup {
            MainAppView()
                .environmentObject(api)
                .environmentObject(tabs)
                .environmentObject(i18n)
                .onAppear { tabs.restoreSessionIfEnabled() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    tabs.saveSessionIfEnabled()
                }
                // Removed manual window tweaks to keep native toolbar/titlebar behavior
        }
        .windowStyle(.titleBar)
        
        Settings {
            SettingsView()
                .environmentObject(api)
                .environmentObject(tabs)
                .environmentObject(i18n)
        }
    }
}
