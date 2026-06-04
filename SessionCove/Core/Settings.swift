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

    /// Posted when `CoveSettings.enabledProviders` changes (user toggles a
    /// framework on/off in the AI 框架 tab). Carries the new set so
    /// `WindowManager` can diff old vs new and run the per-provider
    /// install / uninstall side effects.
    static let coveEnabledProvidersDidChange = Notification.Name("coveEnabledProvidersDidChange")
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
        case preferredTerminal = "covePreferredTerminal"
        case approvalExpandByDefault = "coveApprovalExpandByDefault"
        case silenceCompletionWhenTerminalFrontmost = "coveSilenceCompletionWhenTerminalFrontmost"
        case enabledProviders = "coveEnabledProviders"
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

    /// When true, the approval ping card opens with its detail panel already
    /// expanded — so users who always want to see the full tool_input don't
    /// have to click the chevron every time. Default false (keeps the
    /// original 72pt strip for users who prefer compact).
    @Published var approvalExpandByDefault: Bool {
        didSet {
            guard !bootstrap else { return }
            persist(approvalExpandByDefault, .approvalExpandByDefault)
        }
    }

    /// When true (default), suppress the completion toast if the user is
    /// already focused on a terminal — they can see the result in their
    /// own session and don't need an extra popup. Set to false to always
    /// show the toast regardless of frontmost app. The pending file is
    /// still cleaned up so the toast doesn't appear later when the user
    /// switches away.
    @Published var silenceCompletionWhenTerminalFrontmost: Bool {
        didSet {
            guard !bootstrap else { return }
            persist(silenceCompletionWhenTerminalFrontmost, .silenceCompletionWhenTerminalFrontmost)
        }
    }

    /// User-selected terminal for resume operations. `nil` (the default)
    /// means "auto-detect" — `TerminalDetector.resolvedTerminal()` will
    /// fall back to ancestor detection or installed-list cascade. Set
    /// explicitly when the user picks a terminal in settings.
    @Published var preferredTerminal: TerminalKind? {
        didSet {
            guard !bootstrap else { return }
            persistOptionalTerminal(preferredTerminal)
        }
    }

    /// Set of `AgentProvider.id` values the user has enabled. The
    /// `AgentProviderRegistry.enabled()` query, the per-provider hook
    /// installer, and the AI 框架 settings tab all consult this property.
    ///
    /// Default is `["claude"]` — first launch must NOT auto-enable any
    /// other framework so we never write to `~/.qoder/`, `~/.qoderwork/`,
    /// or `~/.cursor/` without explicit user opt-in. The setter is
    /// belt-and-suspenders defensive: if "claude" is removed (e.g. by a
    /// future code path) it is silently re-inserted before persisting.
    /// The UI also disables the Claude toggle so this branch should
    /// never fire in practice.
    ///
    /// Encoded on disk as a sorted `[String]` array under
    /// `Key.enabledProviders` so a `defaults read` is human-friendly.
    @Published var enabledProviders: Set<String> {
        didSet {
            guard !bootstrap else { return }
            if !enabledProviders.contains("claude") {
                // Claude is mandatory. Re-insert and skip the change-event
                // so observers see exactly one transition (the corrected
                // set) rather than the intermediate invalid state.
                bootstrap = true
                enabledProviders.insert("claude")
                bootstrap = false
            }
            persistEnabledProviders(enabledProviders)
            if oldValue != enabledProviders {
                postNotification(.coveEnabledProvidersDidChange)
            }
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

        if let raw = defaults.string(forKey: Key.preferredTerminal.rawValue),
           let kind = TerminalKind(rawValue: raw) {
            self.preferredTerminal = kind
        } else {
            self.preferredTerminal = nil
        }

        // Default false; explicit-key check so a future "default true" flip
        // doesn't retroactively enable the flag for users who already touched
        // it (matches the soundEnabled / soundVolume defaulting pattern above).
        if defaults.object(forKey: Key.approvalExpandByDefault.rawValue) != nil {
            self.approvalExpandByDefault = defaults.bool(forKey: Key.approvalExpandByDefault.rawValue)
        } else {
            self.approvalExpandByDefault = false
        }

        // Default true — terminal users who just finished a turn already
        // see the result on their own screen.
        if defaults.object(forKey: Key.silenceCompletionWhenTerminalFrontmost.rawValue) != nil {
            self.silenceCompletionWhenTerminalFrontmost = defaults.bool(
                forKey: Key.silenceCompletionWhenTerminalFrontmost.rawValue
            )
        } else {
            self.silenceCompletionWhenTerminalFrontmost = true
        }

        // Enabled provider set. Default is `["claude"]` ONLY — first
        // launch must never auto-enable Qoder / QoderWork / Cursor. The
        // explicit `object(forKey:)` check distinguishes "user has not
        // touched this yet" (use default) from "user disabled everything
        // and we should respect that" (which is impossible because the
        // setter re-inserts claude).
        if let raw = defaults.array(forKey: Key.enabledProviders.rawValue) as? [String],
           !raw.isEmpty {
            var set = Set(raw)
            set.insert("claude")  // belt-and-suspenders against corrupt prefs
            self.enabledProviders = set
        } else {
            self.enabledProviders = ["claude"]
        }

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

    /// Persist `TerminalKind` as its raw string; `nil` removes the key so
    /// auto-detect resumes (matches `preferredScreenID` semantics).
    private func persistOptionalTerminal(_ kind: TerminalKind?) {
        if let kind {
            defaults.set(kind.rawValue, forKey: Key.preferredTerminal.rawValue)
        } else {
            defaults.removeObject(forKey: Key.preferredTerminal.rawValue)
        }
    }

    /// Persist `enabledProviders` as a sorted `[String]` so the on-disk
    /// representation is stable across launches (otherwise Set's
    /// hash-randomized iteration would shuffle the array on every save
    /// and noise up `defaults read` diffs).
    private func persistEnabledProviders(_ ids: Set<String>) {
        defaults.set(ids.sorted(), forKey: Key.enabledProviders.rawValue)
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

// MARK: - Picker support

extension CoveSettings.DisplayMode {
    var iconName: String {
        switch self {
        case .pet: return "pawprint.fill"
        case .notch: return "rectangle.split.3x1.fill"
        }
    }
}

extension CoveSettings.PetAnchorMode: Identifiable {
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .lastPosition: return "上次位置"
        case .topCenter: return "居中顶部"
        }
    }
}

extension CoveSettings.NotchTrigger: Identifiable {
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .hover: return "悬停"
        case .click: return "点击"
        }
    }
}

// MARK: - Helpers

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
