import AppKit

/// Placement math for the Notch-mode panel.
///
/// PR 3 closed state: panel is full-screen-width × 750pt tall, anchored to the
/// screen's top so the notch graphic itself can hover over the menu-bar area.
/// (PR 4 will manage opened/peeking variants by changing panel frame.)
@MainActor
enum NotchPlacementStrategy {
    static let panelHeight: CGFloat = 750

    /// Use `frame`, NOT `visibleFrame`: notch panel must overlay the menu-bar
    /// area so the notch shape itself sits at the very top edge of the display.
    static func panelFrame(for screen: NSScreen) -> NSRect {
        let frame = screen.frame
        return NSRect(
            x: frame.origin.x,
            y: frame.maxY - panelHeight,
            width: frame.width,
            height: panelHeight
        )
    }

    /// The notch graphic's frame within the panel (panel-local coordinates).
    /// Closed: centered horizontally at the very top, sized per
    /// `screen.notchMetrics` or `ScreenNotchMetrics.fallback`.
    static func notchRect(in panelSize: NSSize, metrics: ScreenNotchMetrics) -> NSRect {
        let w = max(metrics.width, ScreenNotchMetrics.fallback.width)
        let h = max(metrics.height, ScreenNotchMetrics.fallback.height)
        return NSRect(
            x: (panelSize.width - w) / 2,
            y: panelSize.height - h,
            width: w,
            height: h
        )
    }
}
