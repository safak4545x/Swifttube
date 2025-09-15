/*
 File Overview (EN)
 Purpose: Overlay to intercept middle-clicks and translate them into tab-opening actions consistent with desktop browsing patterns.
 Key Responsibilities:
 - Capture middle mouse button interactions over views
 - Post notifications or call handlers to open in tabs
 Used By: Video/playlist items to open in new tabs via middle-click.

 Dosya Özeti (TR)
 Amacı: Orta tıklamaları yakalayıp masaüstü tarayıcı alışkanlıklarına uygun olarak sekmede açma eylemlerine çeviren overlay.
 Ana Sorumluluklar:
 - Görünümler üzerinde orta düğme etkileşimlerini yakalamak
 - Sekmede açmak için bildirim/handler çağırmak
 Nerede Kullanılır: Video/playlist öğelerinde orta tıklama ile yeni sekme açma.
*/

import SwiftUI
import AppKit

struct MouseOpenInNewTabCatcher: NSViewRepresentable {
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

		// Only capture middle-clicks; let all other mouse events pass through to underlying SwiftUI views
		override func hitTest(_ point: NSPoint) -> NSView? {
			guard let event = NSApp.currentEvent else { return nil }
			switch event.type {
			case .otherMouseDown, .otherMouseUp, .otherMouseDragged:
				return event.buttonNumber == 2 ? self : nil
			default:
				return nil
			}
		}

		override func otherMouseDown(with event: NSEvent) {
			// Middle button is typically buttonNumber == 2
			if event.buttonNumber == 2 { onMiddleClick() }
		}
		override var isFlipped: Bool { true }
	}
}

