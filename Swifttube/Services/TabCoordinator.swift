/*
 File Overview (EN)
 Purpose: Central tab/session coordinator managing open tabs, activation, restoration, and persistence.
 Key Responsibilities:
 - Open/activate/close/replace tabs and notify content to stop when closing
 - Remember/restore tab sessions using GlobalCaches based on user preference
 - Provide scroll-to-last token for TabStrip auto-scrolling
 Used By: TabHostView/TabStripView and views that open videos/shorts.

 Dosya Özeti (TR)
 Amacı: Açık sekmelerin yönetimi, etkinleştirme, kapatma, oturumun kaydı ve geri yüklenmesini yöneten merkez koordinatör.
 Ana Sorumluluklar:
 - Sekme açma/etkinleştirme/kapatma/değiştirme ve kapatırken içeriğe durdurma bildirimi
 - Kullanıcı tercihi açıksa GlobalCaches ile sekme oturumunu kaydetme/geri yükleme
 - TabStrip otomatik kaydırma için scroll-to-last belirteci üretmek
 Nerede Kullanılır: TabHostView/TabStripView ve video/shorts açan görünümler.
*/

import Foundation
import SwiftUI

@MainActor
class TabCoordinator: ObservableObject {
	@Published var tabs: [AppTab] = []
	@Published var activeTabId: UUID? = nil
	// For TabStripView to auto-scroll to end when a new tab is added
	@Published var scrollToLastToken = UUID()

	// MARK: - Persistence (Remember Tabs)
	private let rememberTabsKey = "preferences:rememberTabsEnabled"
	private let tabsStateKey = "session:openTabs"
	private let activeTabKey = "session:activeTabId"

	/// Call on startup to restore a previous tab session if the user opted in.
	@MainActor
	func restoreSessionIfEnabled() {
		let enabled = UserDefaults.standard.bool(forKey: rememberTabsKey)
		guard enabled else { return }
		Task { @MainActor in
			if let saved: [AppTab] = await GlobalCaches.json.get(key: CacheKey(tabsStateKey), type: [AppTab].self) {
				self.tabs = saved
			}
			if let idStr: String = await GlobalCaches.json.get(key: CacheKey(activeTabKey), type: String.self),
			   let uuid = UUID(uuidString: idStr),
			   self.tabs.contains(where: { $0.id == uuid }) {
				self.activeTabId = uuid
			} else {
				self.activeTabId = self.tabs.first?.id
			}
		}
	}

	/// Call on app termination to save the current tab session if enabled.
	@MainActor
	func saveSessionIfEnabled() {
		let enabled = UserDefaults.standard.bool(forKey: rememberTabsKey)
		guard enabled else { return }
		let openTabs = tabs
		let active = activeTabId?.uuidString
		Task {
			await GlobalCaches.json.set(key: CacheKey(tabsStateKey), value: openTabs, ttl: CacheTTL.sevenDays * 26)
			if let active { await GlobalCaches.json.set(key: CacheKey(activeTabKey), value: active, ttl: CacheTTL.sevenDays * 26) }
		}
	}

	func indexOfTab(forVideoId id: String) -> Int? {
		tabs.firstIndex(where: {
			switch $0.kind {
			case .video(let vid): return vid == id
			case .shorts(let sid): return sid == id
			}
		})
	}

	func openVideoInBackground(videoId: String, title: String, isShorts: Bool, playlist: PlaylistContext? = nil) {
		// If exists, do not create; do nothing (caller may choose to activate)
		if indexOfTab(forVideoId: videoId) != nil { return }
		let kind: TabKind = isShorts ? .shorts(id: videoId) : .video(id: videoId)
		tabs.append(AppTab(title: title, kind: kind, playlist: playlist))
		// do not activate; only request scroll
		scrollToLastToken = UUID()
		// Persist session if the preference is enabled
		saveSessionIfEnabled()
	}

	func openOrActivate(videoId: String, title: String, isShorts: Bool, playlist: PlaylistContext? = nil) {
		if let idx = indexOfTab(forVideoId: videoId) {
			activeTabId = tabs[idx].id
			// Persist session if the preference is enabled (active tab changed)
			saveSessionIfEnabled()
			return
		}
		let kind: TabKind = isShorts ? .shorts(id: videoId) : .video(id: videoId)
		let tab = AppTab(title: title, kind: kind, playlist: playlist)
		tabs.append(tab)
		activeTabId = tab.id
		scrollToLastToken = UUID()
		// Persist session if the preference is enabled
		saveSessionIfEnabled()
	}

	func activate(tab: AppTab) {
		activeTabId = tab.id
		// Persist session if the preference is enabled (active tab changed)
		saveSessionIfEnabled()
	}

	func close(tabId: UUID) {
		guard let idx = tabs.firstIndex(where: { $0.id == tabId }) else { return }
		let wasActive = (activeTabId == tabId)
		// Before removing, broadcast stop for the specific content
		switch tabs[idx].kind {
		case .video(let vid):
			NotificationCenter.default.post(name: .stopVideoId, object: nil, userInfo: ["videoId": vid])
		case .shorts:
			// Shorts has multiple instances; request all to stop
			NotificationCenter.default.post(name: .shortsStopAll, object: nil)
		}
		tabs.remove(at: idx)
		if wasActive {
			// Focus nearest right tab; if none, nearest left
			if idx < tabs.count { activeTabId = tabs[idx].id }
			else if !tabs.isEmpty { activeTabId = tabs.last!.id }
			else { activeTabId = nil }
		}
		// Persist session if the preference is enabled
		saveSessionIfEnabled()
	}

	/// Replace the active tab's content with the given video (or shorts) and persist session.
	func replaceActiveTab(videoId: String, title: String, isShorts: Bool, playlist: PlaylistContext? = nil) {
		guard let activeId = activeTabId, let idx = tabs.firstIndex(where: { $0.id == activeId }) else { return }
		// Update tab model
		tabs[idx].title = title
		tabs[idx].kind = isShorts ? .shorts(id: videoId) : .video(id: videoId)
		// Preserve incoming playlist context if provided (keep existing if nil)
		if let playlist = playlist { tabs[idx].playlist = playlist }
		// Persist session if enabled
		saveSessionIfEnabled()
	}
}

