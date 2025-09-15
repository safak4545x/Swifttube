/*
 Overview / Genel Bakış
 EN: Intercepts middle-clicks and maps them to "open in new tab" actions.
 TR: Orta tıklamayı yakalayıp "yeni sekmede aç" eylemine dönüştürür.
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

		// EN: Capture only middle-clicks; let other events fall through. TR: Sadece orta tıklamayı yakala; diğerlerini alttaki görünüme bırak.
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
			// EN: Middle button is typically buttonNumber == 2. TR: Orta düğme genelde 2 numaradır.
			if event.buttonNumber == 2 { onMiddleClick() }
		}
		override var isFlipped: Bool { true }
	}
}

