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
    /// All four components are ceil'd to integer pixels — `frame.origin.x` and
    /// `frame.width` can come back fractional on 4K externals + DPI swaps,
    /// which causes half-pixel shimmer at the panel edge.
    static func panelFrame(for screen: NSScreen) -> NSRect {
        let frame = screen.frame
        return NSRect(
            x: ceil(frame.origin.x),
            y: ceil(frame.maxY - panelHeight),
            width: ceil(frame.width),
            height: ceil(panelHeight)
        )
    }

    /// The notch graphic's frame within the panel (panel-local coordinates).
    /// Closed: centered horizontally at the very top, sized per
    /// `screen.notchMetrics` or `ScreenNotchMetrics.fallback`. Ceil'd to integer
    /// pixels so the shape's antialiased edge stays crisp regardless of DPI.
    static func notchRect(in panelSize: NSSize, metrics: ScreenNotchMetrics) -> NSRect {
        let w = max(metrics.width, ScreenNotchMetrics.fallback.width)
        let h = max(metrics.height, ScreenNotchMetrics.fallback.height)
        return NSRect(
            x: ceil((panelSize.width - w) / 2),
            y: ceil(panelSize.height - h),
            width: ceil(w),
            height: ceil(h)
        )
    }
}
