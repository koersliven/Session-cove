import AppKit
import SwiftUI

/// Pet anchor geometry helper.
///
/// Persistence is owned by `CoveSettings.shared.petAnchorPoint` (PR 1.B).
/// What remains here is the pure screen-geometry clamp — keeping it on the
/// controller side because `CoveSettings` shouldn't depend on AppKit
/// `NSScreen.visibleFrame`.
enum PetAnchorGeometry {
    /// Clamp the anchor so the full pet rect stays within `visibleFrame`.
    /// If the visible frame is smaller than the pet, the anchor is pinned to the origin.
    static func clamp(_ anchor: NSPoint, petSize: NSSize, into visibleFrame: NSRect) -> NSPoint {
        var p = anchor
        let maxX = visibleFrame.maxX - petSize.width
        let maxY = visibleFrame.maxY - petSize.height
        if p.x < visibleFrame.minX { p.x = visibleFrame.minX }
        if p.x > maxX { p.x = maxX }
        if p.y < visibleFrame.minY { p.y = visibleFrame.minY }
        if p.y > maxY { p.y = maxY }
        return p
    }
}

/// Computes panel frames for the four `CoveFrameSize` cases that the pet
/// controller cycles through (.pet / .compact / .ping / .expanded), and owns
/// the in-memory anchor + previous-frame-size state machine.
///
/// Extracted from `CoveWindowController` so the controller can stay focused
/// on AppKit lifecycle and the placement math is unit-testable in isolation.
@MainActor
final class PetPlacementStrategy {
    static let petSize = NSSize(width: 48, height: 48)
    static let pingCardWidth: CGFloat = 340
    static let pingHeight: CGFloat = 72

    private(set) var petAnchor: NSPoint?
    private(set) var previousFrameSize: CoveFrameSize = .pet

    /// Snapshot panel origin into `petAnchor` when leaving `.pet` for any other
    /// state, so subsequent compact/ping/expanded frames anchor to where the
    /// pet last sat. Caller invokes BEFORE setting the new frame.
    func capturePetAnchorIfLeavingPet(currentFrameSize new: CoveFrameSize, panelOrigin: NSPoint) {
        if previousFrameSize == .pet && new != .pet {
            petAnchor = panelOrigin
        }
        previousFrameSize = new
    }

    /// Initial pet anchor (called on init from saved settings or default).
    func setInitialAnchor(_ anchor: NSPoint?) {
        petAnchor = anchor
    }

    /// User dragged — save panel origin as new anchor.
    func savePetAnchor(_ origin: NSPoint) {
        petAnchor = origin
    }

    /// Compute target frame for the panel given the new logical size,
    /// the panel's current origin (used for compact/ping anchor fallback),
    /// and the screen's visible frame.
    /// Returns the target frame plus, for `.ping`, the expand direction the
    /// caller should set on the view model.
    func nextFrame(
        for frameSize: CoveFrameSize,
        currentPanelOrigin: NSPoint,
        screenFrame: NSRect,
        pingHeightOverride: CGFloat? = nil
    ) -> (frame: NSRect, pingDirection: HorizontalEdge?) {
        let newSize = size(for: frameSize, pingHeightOverride: pingHeightOverride)

        switch frameSize {
        case .pet:
            let origin = petAnchor ?? NSPoint(
                x: screenFrame.midX - newSize.width / 2,
                y: screenFrame.maxY - newSize.height
            )
            return (ceilFrame(NSRect(origin: origin, size: newSize)), nil)

        case .ping:
            let anchor = petAnchor ?? currentPanelOrigin
            let petCenterX = anchor.x + Self.petSize.width / 2
            let expandRight = petCenterX < screenFrame.midX
            let direction: HorizontalEdge = expandRight ? .trailing : .leading

            let originX: CGFloat
            if expandRight {
                originX = anchor.x
            } else {
                originX = anchor.x + Self.petSize.width - newSize.width
            }
            let originY = anchor.y + Self.petSize.height / 2 - newSize.height / 2
            let frame = clampToScreen(
                NSRect(x: originX, y: originY, width: newSize.width, height: newSize.height),
                screen: screenFrame
            )
            return (ceilFrame(frame), direction)

        case .expanded:
            let anchor = petAnchor ?? NSPoint(
                x: screenFrame.midX - Self.petSize.width / 2,
                y: screenFrame.maxY - Self.petSize.height
            )
            let petCenterX = anchor.x + Self.petSize.width / 2
            let petCenterY = anchor.y + Self.petSize.height / 2
            let originX = petCenterX - newSize.width / 2
            let originY = petCenterY - newSize.height + 48
            let frame = clampToScreen(
                NSRect(x: originX, y: originY, width: newSize.width, height: newSize.height),
                screen: screenFrame
            )
            return (ceilFrame(frame), nil)

        case .compact:
            let anchor = petAnchor ?? NSPoint(
                x: screenFrame.midX - Self.petSize.width / 2,
                y: screenFrame.maxY - Self.petSize.height
            )
            let petCenterX = anchor.x + Self.petSize.width / 2
            let originX = petCenterX - newSize.width / 2
            let originY = anchor.y + Self.petSize.height / 2 - newSize.height / 2
            let frame = clampToScreen(
                NSRect(x: originX, y: originY, width: newSize.width, height: newSize.height),
                screen: screenFrame
            )
            return (ceilFrame(frame), nil)
        }
    }

    /// Snap an NSRect to integer pixel boundaries using `ceil`, defending against
    /// fractional pixels (e.g. 412.5, 783.7333) that 4K externals + DPI swaps can
    /// emit. Half-pixel origins cause edge shimmer; ceil overshoots by < 1pt
    /// which is below visual threshold and stays consistent across redraws.
    private func ceilFrame(_ rect: NSRect) -> NSRect {
        NSRect(
            x: ceil(rect.origin.x),
            y: ceil(rect.origin.y),
            width: ceil(rect.size.width),
            height: ceil(rect.size.height)
        )
    }

    private func size(for frameSize: CoveFrameSize, pingHeightOverride: CGFloat? = nil) -> NSSize {
        switch frameSize {
        case .pet:      Self.petSize
        case .compact:  NSSize(width: 300, height: 50)
        case .ping:     NSSize(width: Self.petSize.width + Self.pingCardWidth,
                                height: pingHeightOverride ?? Self.pingHeight)
        case .expanded: NSSize(width: 520, height: 480)
        }
    }

    private func clampToScreen(_ rect: NSRect, screen: NSRect) -> NSRect {
        var r = rect
        if r.maxX > screen.maxX { r.origin.x = screen.maxX - r.width }
        if r.minX < screen.minX { r.origin.x = screen.minX }
        if r.maxY > screen.maxY { r.origin.y = screen.maxY - r.height }
        if r.minY < screen.minY { r.origin.y = screen.minY }
        return r
    }
}
