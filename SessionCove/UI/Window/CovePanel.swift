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
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            if let contentView,
               contentView.hitTest(event.locationInWindow) == nil,
               let cgEvent = event.cgEvent {
                // Hit-test miss; replay through to whatever's underneath.
                MouseEventReplay.mark(cgEvent)
                cgEvent.post(tap: .cghidEventTap)
                return
            }
            makeKey()
        }
        super.sendEvent(event)
    }
}
