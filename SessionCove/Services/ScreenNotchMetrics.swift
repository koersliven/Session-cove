import Foundation
import CoreGraphics

/// Geometric description of a Mac display's notch region.
/// All coordinates are in screen-local space (relative to the screen's frame).
struct ScreenNotchMetrics: Equatable {
    /// Width of the notch itself (the dark cutout).
    let width: CGFloat
    /// Height of the notch (vertical extent below the top edge).
    let height: CGFloat
    /// Horizontal center of the notch in screen-frame x coordinates.
    /// Use to position UI elements relative to the notch.
    let centerX: CGFloat

    /// Sensible defaults for when measurement APIs return zero.
    /// Width 224 / height 32 matches recent Apple Silicon MacBook Pros.
    static let fallback = ScreenNotchMetrics(width: 224, height: 32, centerX: 0)
}
