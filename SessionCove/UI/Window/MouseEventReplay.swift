import AppKit
import CoreGraphics

/// Tag mouse events that we re-post via CGEvent to identify replays.
///
/// Use case: notch panel in closed/peeking state intercepts a mouseDown that
/// missed our hit-rect, replays it via CGEvent.post so it lands on the menu
/// bar (or app underneath). The global click monitor used by
/// CoveWindowController would otherwise interpret the replayed event as
/// "user clicked outside the pet" and try to close the panel — we use this
/// tag to distinguish replays from real clicks.
///
/// Implementation: stamp a sentinel value on `CGEventField.eventSourceUserData`
/// (a 64-bit int slot reserved for application use, not touched by the system)
/// before re-posting; check the same field on the way back into our process.
enum MouseEventReplay {
    /// Sentinel value: ASCII for "SESSION".
    private static let marker: Int64 = 0x53_4553_5349_4F4E

    /// Stamp the marker on a CGEvent before re-posting it via `CGEvent.post`.
    static func mark(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: marker)
    }

    /// True if this NSEvent is one we replayed earlier — call sites should
    /// short-circuit (do nothing) so the event reaches its real target without
    /// triggering our app-level handlers (close, etc.).
    static func isReplayed(_ event: NSEvent) -> Bool {
        event.cgEvent?.getIntegerValueField(.eventSourceUserData) == marker
    }

    /// CGEvent overload (for call sites that already hold a CGEvent).
    static func isReplayed(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == marker
    }
}
