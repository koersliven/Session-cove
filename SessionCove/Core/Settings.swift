import Foundation
import SwiftUI
import ServiceManagement

extension Notification.Name {
    /// Posted when the user switches between Pet and Notch display modes.
    /// Observers (e.g. WindowManager in PR 3) should swap the active controller.
    static let coveDisplayModeDidChange = Notification.Name("coveDisplayModeDidChange")

    /// Posted when the persisted pet anchor changes (drag end, manual reset, etc).
    /// Observers can refresh window placement without reading UserDefaults directly.
    static let covePetAnchorDidChange = Notification.Name("covePetAnchorDidChange")
}

/// Centralized user-facing settings store, backed by `UserDefaults`.
///
/// Replaces the prior `@AppStorage`-on-`ObservableObject` stub which silently
/// failed to publish changes (because `@AppStorage` only triggers
/// `objectWillChange` from a SwiftUI `View`, not from inside an
/// `ObservableObject`). This rewrite uses `@Published` + `didSet`-driven
/// persistence so SwiftUI views subscribed to the store update correctly.
///
/// Storage rules:
/// - All keys are namespaced under the `Key` enum (single source of truth).
/// - `petAnchorPoint` storage matches `PetAnchorPersistence` (`[Double]`)
///   so PR 1.C can swap the persistence backend without data loss.
/// - During `init`, a `bootstrap` flag suppresses the rollback path in
///   `applyLaunchAtLogin` — Swift property observers don't fire for the first
///   assignment in `init`, but the flag is still required for the rollback
///   re-assignment inside `applyLaunchAtLogin` (avoids infinite recursion).
@MainActor
final class CoveSettings: ObservableObject {
    static let shared = CoveSettings()

    // MARK: - Enums

    enum DisplayMode: String, CaseIterable, Codable, Identifiable {
        case pet
        case notch
        var id: String { rawValue }
        var title: String { self == .pet ? "悬浮宠物" : "刘海驻留" }
    }

    enum PetAnchorMode: String, CaseIterable, Codable {
        case topCenter
        case lastPosition
    }

    enum NotchTrigger: String, CaseIterable, Codable {
        case hover
        case click
    }

    // MARK: - Storage keys

    private enum Key: String {
        case displayMode      = "coveDisplayMode"
        case fontSize         = "coveContentFontSize"
        case launchAtLogin    = "coveLaunchAtLogin"
        case soundEnabled     = "coveSoundEnabled"
        case soundVolume      = "coveSoundVolume"
        case screenID         = "covePreferredScreenID"
        case petAnchorMode    = "covePetAnchorMode"
        case petAnchorPoint   = "covePetAnchorPoint"  // matches PetAnchorPersistence.defaultsKey
        case notchTrigger     = "coveNotchTrigger"
        case showArchived     = "showArchivedSessions"
    }

    /// Allowed range for `contentFontSize`. Exposed for PR 2's slider.
    static let fontSizeRange: ClosedRange<Double> = 11.0...17.0

    // MARK: - Published fields

    @Published var displayMode: DisplayMode {
        didSet {
            guard !bootstrap else { return }
            persist(displayMode.rawValue, .displayMode)
            if oldValue != displayMode {
                postNotification(.coveDisplayModeDidChange)
            }
        }
    }

    @Published var contentFontSize: Double {
        didSet {
            guard !bootstrap else { return }
            let clamped = contentFontSize.clamped(to: Self.fontSizeRange)
            if clamped != contentFontSize {
                contentFontSize = clamped
                return
            }
            persist(contentFontSize, .fontSize)
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard !bootstrap else { return }
            applyLaunchAtLogin()
        }
    }

    @Published var soundEnabled: Bool {
        didSet {
            guard !bootstrap else { return }
            persist(soundEnabled, .soundEnabled)
        }
    }

    @Published var soundVolume: Double {
        didSet {
            guard !bootstrap else { return }
            let clamped = soundVolume.clamped(to: 0.0...1.0)
            if clamped != soundVolume {
                soundVolume = clamped
                return
            }
            persist(soundVolume, .soundVolume)
        }
    }

    @Published var preferredScreenID: CGDirectDisplayID? {
        didSet {
            guard !bootstrap else { return }
            persistOptionalScreenID(preferredScreenID)
        }
    }

    @Published var petAnchorMode: PetAnchorMode {
        didSet {
            guard !bootstrap else { return }
            persist(petAnchorMode.rawValue, .petAnchorMode)
        }
    }

    @Published var petAnchorPoint: NSPoint? {
        didSet {
            guard !bootstrap else { return }
            persistPoint(petAnchorPoint)
            if oldValue != petAnchorPoint {
                postNotification(.covePetAnchorDidChange)
            }
        }
    }

    @Published var notchTrigger: NotchTrigger {
        didSet {
            guard !bootstrap else { return }
            persist(notchTrigger.rawValue, .notchTrigger)
        }
    }

    @Published var showArchivedSessions: Bool {
        didSet {
            guard !bootstrap else { return }
            persist(showArchivedSessions, .showArchived)
        }
    }

    // MARK: - Internals

    private let defaults: UserDefaults
    private var bootstrap = true

    /// `defaults` parameter is exposed for tests; production callers always go
    /// through `.shared` which uses `UserDefaults.standard`.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Load all fields from UserDefaults. Property observers don't fire on
        // initial assignment, so these reads do NOT trigger persistence.
        let modeRaw = defaults.string(forKey: Key.displayMode.rawValue)
            ?? DisplayMode.pet.rawValue
        self.displayMode = DisplayMode(rawValue: modeRaw) ?? .pet

        if defaults.object(forKey: Key.fontSize.rawValue) != nil {
            self.contentFontSize = defaults.double(forKey: Key.fontSize.rawValue)
                .clamped(to: Self.fontSizeRange)
        } else {
            self.contentFontSize = 13.0
        }

        // launchAtLogin defaults to false; SMAppService is queried lazily by the
        // toggle, not here, so we don't reconcile OS state on init.
        self.launchAtLogin = defaults.bool(forKey: Key.launchAtLogin.rawValue)

        if defaults.object(forKey: Key.soundEnabled.rawValue) != nil {
            self.soundEnabled = defaults.bool(forKey: Key.soundEnabled.rawValue)
        } else {
            self.soundEnabled = true
        }

        if defaults.object(forKey: Key.soundVolume.rawValue) != nil {
            self.soundVolume = defaults.double(forKey: Key.soundVolume.rawValue)
                .clamped(to: 0.0...1.0)
        } else {
            self.soundVolume = 0.6
        }

        if defaults.object(forKey: Key.screenID.rawValue) != nil {
            let raw = defaults.integer(forKey: Key.screenID.rawValue)
            self.preferredScreenID = raw > 0 ? CGDirectDisplayID(raw) : nil
        } else {
            self.preferredScreenID = nil
        }

        let anchorRaw = defaults.string(forKey: Key.petAnchorMode.rawValue)
            ?? PetAnchorMode.lastPosition.rawValue
        self.petAnchorMode = PetAnchorMode(rawValue: anchorRaw) ?? .lastPosition

        if let array = defaults.array(forKey: Key.petAnchorPoint.rawValue) as? [Double],
           array.count == 2 {
            self.petAnchorPoint = NSPoint(x: array[0], y: array[1])
        } else {
            self.petAnchorPoint = nil
        }

        let triggerRaw = defaults.string(forKey: Key.notchTrigger.rawValue)
            ?? NotchTrigger.hover.rawValue
        self.notchTrigger = NotchTrigger(rawValue: triggerRaw) ?? .hover

        self.showArchivedSessions = defaults.bool(forKey: Key.showArchived.rawValue)

        bootstrap = false
    }

    // MARK: - Persistence helpers

    private func persist<T>(_ value: T, _ key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }

    private func persistOptionalScreenID(_ id: CGDirectDisplayID?) {
        if let id {
            defaults.set(Int(id), forKey: Key.screenID.rawValue)
        } else {
            defaults.removeObject(forKey: Key.screenID.rawValue)
        }
    }

    /// Persist NSPoint as `[Double]` (x, y). Format intentionally matches
    /// `PetAnchorPersistence` so PR 1.C can hand off ownership transparently.
    private func persistPoint(_ point: NSPoint?) {
        guard let point else {
            defaults.removeObject(forKey: Key.petAnchorPoint.rawValue)
            return
        }
        defaults.set([Double(point.x), Double(point.y)],
                     forKey: Key.petAnchorPoint.rawValue)
    }

    private func postNotification(_ name: Notification.Name) {
        guard !bootstrap else { return }
        NotificationCenter.default.post(name: name, object: self)
    }

    /// Apply launch-at-login by registering/unregistering with `SMAppService`.
    /// On failure, roll back the toggle so the UI reflects the real state.
    private func applyLaunchAtLogin() {
        let target = launchAtLogin
        do {
            if target {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            persist(target, .launchAtLogin)
        } catch {
            // Avoid showing the user a "successful" toggle that didn't actually
            // change OS state. Bootstrap flag keeps the rollback assignment
            // from re-entering applyLaunchAtLogin.
            print("[CoveSettings] launchAtLogin update failed: \(error.localizedDescription)")
            bootstrap = true
            launchAtLogin = !target
            bootstrap = false
        }
    }
}

// MARK: - Helpers

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
