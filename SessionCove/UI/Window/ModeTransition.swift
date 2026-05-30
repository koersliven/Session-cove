import SwiftUI

/// Mode-switch transition specs (pet ↔ notch).
///
/// Used by WindowManager.swap to gate input + drive the cross-controller
/// content morph that bridges the two panels visually. Both directions are
/// modeled as single springs — pet→notch uses a longer response so the
/// motion overshoots a touch before snapping in, which feels like the pet
/// "rising up to dock" at the notch; notch→pet is slightly faster + stiffer
/// so the drop feels gravity-led rather than floaty.
enum ModeTransition {
    /// pet → notch: 540ms spring (rise + settle).
    static let petToNotchDuration: TimeInterval = 0.540

    /// notch → pet: 480ms spring (drop + settle).
    static let notchToPetDuration: TimeInterval = 0.480

    /// Animation used to drive a SwiftUI value-change morph between modes.
    /// Falls back to a generic short spring when source/destination collapse
    /// (e.g. pet→pet on persisted-mode bootstrap), so callers never have to
    /// special-case "no-op" transitions.
    static func animation(from oldMode: CoveSettings.DisplayMode,
                          to newMode: CoveSettings.DisplayMode) -> Animation {
        switch (oldMode, newMode) {
        case (.pet, .notch):
            return .spring(response: 0.54, dampingFraction: 0.78, blendDuration: 0)
        case (.notch, .pet):
            return .spring(response: 0.48, dampingFraction: 0.82, blendDuration: 0)
        default:
            return .spring(response: 0.40, dampingFraction: 0.85, blendDuration: 0)
        }
    }

    /// Duration matching `animation(from:to:)`. Used by the input-gate timer
    /// in WindowManager — the Picker is disabled for `duration + small
    /// buffer` so users can't double-fire a swap mid-spring.
    static func duration(from oldMode: CoveSettings.DisplayMode,
                         to newMode: CoveSettings.DisplayMode) -> TimeInterval {
        switch (oldMode, newMode) {
        case (.pet, .notch): return petToNotchDuration
        case (.notch, .pet): return notchToPetDuration
        default: return 0.40
        }
    }
}

/// Singleton flag observed by SwiftUI views (e.g. GeneralTab's DisplayMode
/// Picker) to disable input while a mode swap is animating. WindowManager
/// flips `isTransitioning` to `true` at swap start and back to `false` after
/// the matching `ModeTransition.duration` elapses; CoveViewModel mirrors the
/// same flag for non-SwiftUI consumers (NotchHoverDetector etc.).
@Observable
@MainActor
final class ModeTransitionState {
    static let shared = ModeTransitionState()
    var isTransitioning: Bool = false
    private init() {}
}
