/*
 Overview / Genel Bakış
 EN: Visual tab strip to switch between open video tabs; supports scrolling, close buttons, and active styling.
 TR: Açık video sekmeleri arasında geçiş için görsel şerit; kaydırma, kapatma ve aktif stil desteği.
*/

// EN: SwiftUI view rendering a horizontal tab strip. TR: Yatay sekme şeridi çizen SwiftUI görünümü.
import SwiftUI

// EN: Tab strip bound to TabCoordinator. TR: TabCoordinator'a bağlı sekme şeridi.
struct TabStripView: View {
	@ObservedObject var tabs: TabCoordinator
	@State private var tabStartIndex: Int = 0
	private let tabPageStep: Int = 4

	var body: some View {
		// EN: Hide strip when there are no tabs. TR: Sekme yoksa şeridi gizle.
		if tabs.tabs.isEmpty {
			EmptyView()
		} else {
		HStack(spacing: 6) {
			// EN: Pinned Home button at far left. TR: Solda sabit Home düğmesi.
			Button(action: { NotificationCenter.default.post(name: .goHome, object: nil) }) {
				HStack(spacing: 0) {
					Image(systemName: "house.fill").font(.system(size: 12, weight: .semibold))
				}
				.padding(.horizontal, 10)
				.padding(.vertical, 6)
				.background(
					RoundedRectangle(cornerRadius: 8)
						.fill(Color.secondary.opacity(0.12))
						.overlay(
							RoundedRectangle(cornerRadius: 8)
								.stroke(Color.secondary.opacity(0.3), lineWidth: 1)
						)
				)
			}
			.buttonStyle(.plain)
			.help("Ana sayfaya git")

			// EN: Scrollable tabs area. TR: Kaydırılabilir sekmeler alanı.
			if !tabs.tabs.isEmpty {
				ScrollViewReader { proxy in
					ZStack {
						ScrollView(.horizontal, showsIndicators: false) {
							HStack(spacing: 6) {
								ForEach(tabs.tabs) { tab in
									TabChip(tab: tab,
											isActive: tab.id == tabs.activeTabId,
											onActivate: { tabs.activate(tab: tab) },
											onClose: { tabs.close(tabId: tab.id) })
										.id(tab.id)
								}
							}
						}

						// EN: Page left through tabs. TR: Sekmelerde sola sayfala.
						.overlay(alignment: .leading) {
							if !tabs.tabs.isEmpty {
								let canGoLeft = tabStartIndex > 0
								Button {
									guard canGoLeft else { return }
									let newIndex = max(0, tabStartIndex - tabPageStep)
									withAnimation(.easeOut(duration: 0.22)) {
										proxy.scrollTo(tabs.tabs[newIndex].id, anchor: .leading)
									}
									tabStartIndex = newIndex
								} label: {
									Image(systemName: "chevron.left")
										.font(.system(size: 13, weight: .bold))
										.foregroundColor(.primary)
										.frame(width: 24, height: 24)
								}
								.buttonStyle(.plain)
								.background(
									VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
										.clipShape(Circle())
								)
								.overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
								.opacity(canGoLeft ? 1.0 : 0.35)
								.disabled(!canGoLeft)
							}
						}

						// EN: Page right through tabs. TR: Sekmelerde sağa sayfala.
						.overlay(alignment: .trailing) {
							if !tabs.tabs.isEmpty {
								let lastStart = max(0, tabs.tabs.count - 1 - tabPageStep)
								let canGoRight = tabStartIndex < lastStart
								Button {
									guard canGoRight else { return }
									let newIndex = min(tabStartIndex + tabPageStep, tabs.tabs.count - 1)
									withAnimation(.easeOut(duration: 0.22)) {
										proxy.scrollTo(tabs.tabs[newIndex].id, anchor: .leading)
									}
									tabStartIndex = newIndex
								} label: {
									Image(systemName: "chevron.right")
										.font(.system(size: 13, weight: .bold))
										.foregroundColor(.primary)
										.frame(width: 24, height: 24)
								}
								.buttonStyle(.plain)
								.background(
									VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
										.clipShape(Circle())
								)
								.overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
								.opacity(canGoRight ? 1.0 : 0.35)
								.disabled(!canGoRight)
							}
						}
					}
					.onChange(of: tabs.scrollToLastToken) { _, _ in
						if let last = tabs.tabs.last { withAnimation { proxy.scrollTo(last.id, anchor: .trailing) } }
					}
					.onChange(of: tabs.tabs.count) { _, _ in
						// EN: Keep start index within bounds when count changes. TR: Sayı değişince başlangıcı aralıkta tut.
						tabStartIndex = min(tabStartIndex, max(0, tabs.tabs.count - 1))
					}
				}
			}
		}
		.padding(.horizontal, 8)
		.padding(.vertical, 6)
		.background(
			// EN: Titlebar-like blur background with top hairline. TR: Başlık çubuğu benzeri blur arka plan ve üst çizgi.
			VisualEffectView(material: .titlebar, blendingMode: .withinWindow)
				.overlay(alignment: .top) {
					Rectangle().fill(Color(NSColor.separatorColor).opacity(0.18)).frame(height: 0.5)
				}
		)
		}
	}
}

// EN: A single tab chip with title and close button. TR: Başlık ve kapatma düğmesi olan tek bir sekme çipi.
private struct TabChip: View {
	let tab: AppTab
	let isActive: Bool
	let onActivate: () -> Void
	let onClose: () -> Void

	var body: some View {
		HStack(spacing: 8) {
			Text(truncated(tab.title))
				.font(.system(size: 12, weight: .medium))
				.lineLimit(1)
				.foregroundColor(isActive ? .accentColor : .primary)
			Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 10)) }
				.buttonStyle(.plain)
				.foregroundColor(.secondary)
		}
		.padding(.horizontal, 10)
		.padding(.vertical, 6)
		.background(
			RoundedRectangle(cornerRadius: 8)
				.fill(isActive ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.12))
				.overlay(
					RoundedRectangle(cornerRadius: 8)
						.stroke(isActive ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.3), lineWidth: 1)
				)
		)
		.contentShape(Rectangle())
		.onTapGesture { onActivate() }
		.onHover { hovering in
			if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
		}
		// EN: Capture only middle-click to close; left-clicks pass through. TR: Sadece orta tıkla kapat; sol tıklar geçer.
		.overlay(MiddleClickCatcher(onMiddleClick: onClose).allowsHitTesting(true))
	}
	private func truncated(_ s: String) -> String {
		if s.count <= 24 { return s }
		let idx = s.index(s.startIndex, offsetBy: 24)
		return String(s[..<idx]) + "…"
	}
}

// EN: Catch ONLY middle mouse without blocking other clicks. TR: Diğer tıklamaları engellemeden SADECE orta tıklamayı yakala.
private struct MiddleClickCatcher: NSViewRepresentable {
	let onMiddleClick: () -> Void
	func makeNSView(context: Context) -> NSView { Catcher(onMiddleClick: onMiddleClick) }
	func updateNSView(_ nsView: NSView, context: Context) {}

	final class Catcher: NSView {
		let onMiddleClick: () -> Void
		init(onMiddleClick: @escaping () -> Void) {
			self.onMiddleClick = onMiddleClick
			super.init(frame: .zero)
			wantsLayer = false
		}
		required init?(coder: NSCoder) { fatalError() }
		override func hitTest(_ point: NSPoint) -> NSView? {
			// Only intercept for middle-mouse events; let all others pass through
			if let event = NSApp.currentEvent, event.type == .otherMouseDown { return self }
			return nil
		}
		override func otherMouseDown(with event: NSEvent) {
			if event.buttonNumber == 2 { onMiddleClick() }
		}
		override var isFlipped: Bool { true }
	}
}

