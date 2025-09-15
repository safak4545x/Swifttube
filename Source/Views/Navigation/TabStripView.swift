/*
 File Overview (EN)
 Purpose: Visual tab strip UI for switching between open video tabs.
 Key Responsibilities:
 - Show tab titles, close buttons, and active state
 - Provide scrolling when tabs overflow
 Used By: Shown globally via SheetManagementView.

 Dosya Özeti (TR)
 Amacı: Açık video sekmeleri arasında geçiş için görsel sekme şeridi UI.
 Ana Sorumluluklar:
 - Sekme başlıkları, kapatma butonları ve aktif durumu göstermek
 - Sekmeler taşınca kaydırma sağlamak
 Nerede Kullanılır: SheetManagementView üzerinden global olarak gösterilir.
*/

import SwiftUI

struct TabStripView: View {
	@ObservedObject var tabs: TabCoordinator
	@State private var tabStartIndex: Int = 0
	private let tabPageStep: Int = 4

	var body: some View {
		// Hide the whole strip when there are no tabs (other than the pinned Home button)
		if tabs.tabs.isEmpty {
			EmptyView()
		} else {
		HStack(spacing: 6) {
			// Pinned Home button at the far left (non-scrollable)
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

			// Scrollable tabs area (only when there are tabs)
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

						// SOLA KAYDIR
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

						// SAĞA KAYDIR
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
						// Sekme sayısı değişince başlangıcı güvenli aralıkta tut
						tabStartIndex = min(tabStartIndex, max(0, tabs.tabs.count - 1))
					}
				}
			}
		}
		.padding(.horizontal, 8)
		.padding(.vertical, 6)
		.background(
			// Native blur similar to title bar
			VisualEffectView(material: .titlebar, blendingMode: .withinWindow)
				.overlay(alignment: .top) {
					Rectangle().fill(Color(NSColor.separatorColor).opacity(0.18)).frame(height: 0.5)
				}
		)
		}
	}
}

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
		// Capture only middle-click to close; left-clicks pass through to Button/onTapGesture
		.overlay(MiddleClickCatcher(onMiddleClick: onClose).allowsHitTesting(true))
	}
	private func truncated(_ s: String) -> String {
		if s.count <= 24 { return s }
		let idx = s.index(s.startIndex, offsetBy: 24)
		return String(s[..<idx]) + "…"
	}
}

// NSViewRepresentable to catch ONLY middle mouse button without blocking normal clicks
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

