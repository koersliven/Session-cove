import AppKit
import SwiftUI

struct PetInteractionView: NSViewRepresentable {
    var onTap: () -> Void
    var onDragStart: () -> Void
    var onDragUpdate: (CGSize) -> Void
    var onDragEnd: () -> Void

    func makeNSView(context: Context) -> PetMouseView {
        let view = PetMouseView()
        view.onTap = onTap
        view.onDragStart = onDragStart
        view.onDragUpdate = onDragUpdate
        view.onDragEnd = onDragEnd
        return view
    }

    func updateNSView(_ nsView: PetMouseView, context: Context) {
        nsView.onTap = onTap
        nsView.onDragStart = onDragStart
        nsView.onDragUpdate = onDragUpdate
        nsView.onDragEnd = onDragEnd
    }
}

final class PetMouseView: NSView {
    var onTap: (() -> Void)?
    var onDragStart: (() -> Void)?
    var onDragUpdate: ((CGSize) -> Void)?
    var onDragEnd: (() -> Void)?

    private var mouseDownPoint: NSPoint?
    private var windowStartOrigin: NSPoint?
    private var isDragging = false
    private let dragThreshold: CGFloat = 3

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = NSEvent.mouseLocation
        windowStartOrigin = window?.frame.origin
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startPoint = mouseDownPoint,
              let startOrigin = windowStartOrigin else { return }

        let current = NSEvent.mouseLocation
        let dx = current.x - startPoint.x
        let dy = current.y - startPoint.y

        if !isDragging {
            let distance = sqrt(dx * dx + dy * dy)
            guard distance > dragThreshold else { return }
            isDragging = true
            onDragStart?()
        }

        let newOrigin = NSPoint(
            x: startOrigin.x + dx,
            y: startOrigin.y + dy
        )
        window?.setFrameOrigin(newOrigin)
        onDragUpdate?(CGSize(width: dx, height: dy))
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            onDragEnd?()
        } else {
            onTap?()
        }
        mouseDownPoint = nil
        windowStartOrigin = nil
        isDragging = false
    }
}
