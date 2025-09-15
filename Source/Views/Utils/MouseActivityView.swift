/*
 File Overview (EN)
 Purpose: Utility view that detects mouse movement/hover to drive UI reactions (auto-hide controls, show scroll buttons, etc.).
 Key Responsibilities:
 - Track mouse movement and hover state within a region
 - Publish changes via bindings/closures
 Used By: Scroll button reveals, overlay controls.

 Dosya Özeti (TR)
 Amacı: Fare hareketi/hover algılayıp UI tepkilerini tetikleyen yardımcı görünüm (kontrol gizleme/gösterme vb.).
 Ana Sorumluluklar:
 - Bir bölge içinde fare hareketi ve hover durumunu izlemek
 - Değişimleri binding/closure ile dışarı aktarmak
 Nerede Kullanılır: Kaydırma butonları ve overlay kontrollerinin görünümü.
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
            window?.acceptsMouseMovedEvents = true
        }

        override func mouseEntered(with event: NSEvent) { onEvent?(.entered) }
        override func mouseExited(with event: NSEvent) { onEvent?(.exited) }
        override func mouseMoved(with event: NSEvent) { onEvent?(.moved) }
    }
}

#else
/// iOS/no-AppKit fallback: renders nothing and emits no events.
public struct MouseActivityView: View {
    public init(onEvent: @escaping (_: Never) -> Void) {}
    public var body: some View { Color.clear }
}
#endif
