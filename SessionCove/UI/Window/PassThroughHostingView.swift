import AppKit
import SwiftUI

/// A hosting view that only accepts clicks within configurable hit rects.
/// Points outside those rects pass through to views/windows behind.
final class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    var hitTestRectProvider: (() -> [NSRect])?

    override func hitTest(_ point: NSPoint) -> NSView? {
        let rects = hitTestRectProvider?() ?? [bounds]
        guard rects.contains(where: { $0.contains(point) }) else {
            return nil
        }
        return super.hitTest(point)
    }

    /// Accept first mouse click without requiring prior activation.
    /// Critical for non-activating panels where buttons must respond immediately.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
