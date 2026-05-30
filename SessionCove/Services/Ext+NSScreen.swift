import AppKit
import CoreGraphics

extension NSScreen {
    /// The built-in display (laptop's primary screen with potential notch).
    /// Returns nil on iMac/Mac mini/Mac Pro setups with no built-in display.
    static var builtin: NSScreen? {
        NSScreen.screens.first { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                return false
            }
            return CGDisplayIsBuiltin(id) != 0
        }
    }

    /// Notch metrics for this screen if it has a notch; nil otherwise.
    var notchMetrics: ScreenNotchMetrics? {
        let topInset = safeAreaInsets.top
        guard topInset > 0 else { return nil }

        let leftArea = auxiliaryTopLeftArea
        let rightArea = auxiliaryTopRightArea

        if let leftArea, let rightArea {
            let notchWidth = frame.width - leftArea.width - rightArea.width
            guard notchWidth > 0 else {
                return ScreenNotchMetrics(
                    width: ScreenNotchMetrics.fallback.width,
                    height: topInset,
                    centerX: frame.width / 2
                )
            }
            let centerX = leftArea.width + notchWidth / 2
            return ScreenNotchMetrics(width: notchWidth, height: topInset, centerX: centerX)
        }

        return ScreenNotchMetrics(
            width: ScreenNotchMetrics.fallback.width,
            height: topInset,
            centerX: frame.width / 2
        )
    }
}
