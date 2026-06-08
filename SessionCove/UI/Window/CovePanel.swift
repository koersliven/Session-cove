import AppKit

final class CovePanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        level = .mainMenu + 3
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        titlebarAppearsTransparent = true
        isMovable = false
        isMovableByWindowBackground = false

        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle
        ]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        // Critical: a replayed event is one WE just re-posted via
        // cgEvent.post. Because the panel is still topmost when the event
        // re-enters the HID stream, it lands right back on us. Without this
        // short-circuit, every transparent-area click triggered an infinite
        // replay loop — the visible symptom was "the whole screen freezes,
        // but switching Spaces unfreezes it" because the Space switch
        // briefly suspends the event tap and lets the queue drain.
        if MouseEventReplay.isReplayed(event) {
            // Briefly drop ourselves out of the mouse path so this replayed
            // click can land on whatever is *underneath* the panel. Restore
            // on the next runloop tick — by then the event will have been
            // dispatched. Without this, AppKit re-targets the panel and the
            // click never reaches the menu bar / desktop / app below.
            ignoresMouseEvents = true
            DispatchQueue.main.async { [weak self] in
                self?.ignoresMouseEvents = false
            }
            return
        }

        // Right-click (including trackpad two-finger tap) needs key status
        // BEFORE super.sendEvent, otherwise SwiftUI's .contextMenu won't fire.
        if event.type == .rightMouseDown {
            if let contentView,
               contentView.hitTest(event.locationInWindow) == nil,
               let cgEvent = event.cgEvent {
                MouseEventReplay.mark(cgEvent)
                cgEvent.post(tap: .cghidEventTap)
                return
            }
            makeKey()
            super.sendEvent(event)
            return
        }

        if event.type == .leftMouseDown {
            if let contentView,
               contentView.hitTest(event.locationInWindow) == nil,
               let cgEvent = event.cgEvent {
                // Hit-test miss; replay through to whatever's underneath.
                MouseEventReplay.mark(cgEvent)
                cgEvent.post(tap: .cghidEventTap)
                return
            }
        }
        super.sendEvent(event)
    }
}
