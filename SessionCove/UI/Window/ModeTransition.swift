import SwiftUI

/// Mode-switch transition specs (pet ↔ notch).
///
/// Used by WindowManager.swap to gate input + drive the cross-controller
/// content morph that bridges the two panels visually.
///
/// pet → notch (T9): two-stage feel via `interpolatingSpring` with a non-zero
/// `initialVelocity` — the pet appears to *launch* upward before being caught
/// and locked into the notch. Stiffness/damping are tuned so the visual
/// "response" stays ≈ 0.54s (matching `petToNotchDuration`) but the system is
/// slightly more damped (ζ ≈ 0.88) than the symmetric `.spring(0.54, 0.78)`
/// it replaces, killing the bounce on lock-in.
///
/// notch → pet (T10): kept as a plain critically-damped-ish spring — the pet
/// "drops" out of the notch and we don't want any pre-launch impulse, so a
/// single `.spring(0.48, 0.82)` reads as gravity-led settle.
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
            // T9 two-stage: pet 飞向 notch 时先有上升冲量再被 notch 锁定。
            // ω₀ = 2π / response ≈ 11.6 rad/s with response ≈ 0.54s, so for
            // mass = 1 we get stiffness = ω₀² ≈ 135. Critical damping would be
            // 2·sqrt(stiffness·mass) ≈ 23.2; damping = 20.5 puts ζ ≈ 0.88,
            // slightly tighter than the prior 0.78 so the lock-in doesn't
            // bounce. initialVelocity = 0.6 injects the "launch" impulse that
            // makes the rise feel two-stage instead of a flat ease.
            return .interpolatingSpring(
                mass: 1.0,
                stiffness: 135,
                damping: 20.5,
                initialVelocity: 0.6
            )
        case (.notch, .pet):
            // T10 single spring: notch→pet 是"下落"，不需要 initialVelocity
            // 注入。保持原 0.48 / 0.82 配方。
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
