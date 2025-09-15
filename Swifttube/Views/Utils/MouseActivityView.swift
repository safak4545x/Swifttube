/*
 Overview / Genel Bakış
 EN: Detect hover/mouse movement to drive UI (auto-hide controls, reveal buttons).
 TR: UI tepkilerini tetiklemek için hover/fare hareketi algılar.
*/

import SwiftUI

#if canImport(AppKit)
import AppKit

/// A transparent NSView-backed SwiftUI view that reports mouse enter/exit/move events
/// within its bounds. Useful for auto-hiding controls on macOS.
public struct MouseActivityView: NSViewRepresentable {
    public enum Event { case entered, exited, moved }
    let onEvent: (Event) -> Void

    public init(onEvent: @escaping (Event) -> Void) {
        self.onEvent = onEvent
    }

    public func makeNSView(context: Context) -> NSView {
        let view = TrackingView()
        view.onEvent = onEvent
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        guard let v = nsView as? TrackingView else { return }
        v.onEvent = onEvent
    }

    private final class TrackingView: NSView {
        var onEvent: ((Event) -> Void)?
        private var trackingArea: NSTrackingArea?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor
        }

        required init?(coder: NSCoder) { super.init(coder: coder) }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let ta = trackingArea { removeTrackingArea(ta) }
            let options: NSTrackingArea.Options = [
                .activeInKeyWindow,
                .inVisibleRect,
                .mouseEnteredAndExited,
                .mouseMoved
            ]
            trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
            addTrackingArea(trackingArea!)
            window?.acceptsMouseMovedEvents = true // EN: Ensure mouseMoved events are delivered. TR: mouseMoved olaylarının iletilmesini sağlar.
        }

        override func mouseEntered(with event: NSEvent) { onEvent?(.entered) }
        override func mouseExited(with event: NSEvent) { onEvent?(.exited) }
        override func mouseMoved(with event: NSEvent) { onEvent?(.moved) }
    }
}

#else
/// EN: iOS/no-AppKit fallback: renders nothing and emits no events. TR: iOS/AppKit olmayan ortamda boş görünüm, olay yok.
public struct MouseActivityView: View {
    public init(onEvent: @escaping (_: Never) -> Void) {}
    public var body: some View { Color.clear }
}
#endif
