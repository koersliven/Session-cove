import AppKit
import SwiftUI

@MainActor
final class WindowManager {
    private var controller: CoveModeWindowController?
    private var viewModel: CoveViewModel?
    private var displayModeObserver: NSObjectProtocol?
    private var enabledProvidersObserver: NSObjectProtocol?

    /// Snapshot of the last enabled-provider set we acted on. Used by the
    /// `coveEnabledProvidersDidChange` handler to compute newly-enabled vs
    /// newly-disabled diffs without re-scanning settings files. Seeded
    /// from `CoveSettings.shared.enabledProviders` after the initial
    /// install fan-out completes.
    private var lastEnabledProviders: Set<String> = []

    func setup() {
        let viewModel = CoveViewModel()
        self.viewModel = viewModel
        MenuActionTarget.shared.viewModel = viewModel

        // Start Unix socket server BEFORE installing hooks — the bridge
        // needs the socket to be listening when Claude calls it.
        HookSocketServer.shared.start()

        do {
            try ClaudePermissionHook.install()
            viewModel.startHookPolling()
        } catch {
            viewModel.hookIntegrationError = error.localizedDescription
        }

        // Phase 2 — Codex app-server takeover. When Codex is enabled, SC
        // hosts a `codex app-server` and drives its full interactive
        // protocol (command/file/permission approvals + userInput questions)
        // over WebSocket, surfacing through the same pending/response queue
        // as the hook path. Only started when the user has Codex enabled.
        if CoveSettings.shared.enabledProviders.contains("codex") {
            Task { await CodexAppServerClient.shared.start() }
        }
        // Seed the diff cache AFTER the initial fan-out. Any subsequent
        // change notification will compute (new \ old) and (old \ new)
        // against this snapshot.
        lastEnabledProviders = CoveSettings.shared.enabledProviders

        installController(for: CoveSettings.shared.displayMode, viewModel: viewModel)

        // Defer the swap one runloop tick so SwiftUI Picker can finish committing
        // its binding before we tear down/rebuild the controller (avoids a
        // commit-vs-deinit race that freezes the UI). The inner `[weak self]`
        // recapture is required: NotificationCenter's @Sendable closure gives
        // us a captured weak var that cannot cross into another Sendable closure.
        displayModeObserver = NotificationCenter.default.addObserver(
            forName: .coveDisplayModeDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    self?.swapForCurrentMode()
                }
            }
        }

        // Provider toggle observer: fan out per-provider install /
        // uninstall when the user flips a switch in the AI 框架 tab.
        // Idempotent — installing an already-installed provider is a
        // safe overwrite, uninstalling a never-installed provider is a
        // no-op.
        // Mirror displayModeObserver's [weak self] double-capture pattern:
        // the outer NotificationCenter closure is @Sendable and cannot
        // forward a captured weak var into another Sendable closure.
        enabledProvidersObserver = NotificationCenter.default.addObserver(
            forName: .coveEnabledProvidersDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    self?.handleEnabledProvidersChange()
                }
            }
        }

        Task { await viewModel.initialScan() }
    }

    func teardown() {
        if let observer = displayModeObserver {
            NotificationCenter.default.removeObserver(observer)
            displayModeObserver = nil
        }
        if let observer = enabledProvidersObserver {
            NotificationCenter.default.removeObserver(observer)
            enabledProvidersObserver = nil
        }
        viewModel?.stopHookPolling()
        Task { await CodexAppServerClient.shared.stop() }
        controller?.handleDisplayModeWillChange()
        controller?.close()
        controller = nil
        viewModel = nil
    }

    /// Diff the cached enabled set against the current `CoveSettings`
    /// state and route each delta to the right per-provider hook
    /// installer. Invoked by the `.coveEnabledProvidersDidChange`
    /// notification.
    private func handleEnabledProvidersChange() {
        let current = CoveSettings.shared.enabledProviders
        let added = current.subtracting(lastEnabledProviders)
        let removed = lastEnabledProviders.subtracting(current)
        lastEnabledProviders = current

        for providerId in added {
            switch providerId {
            case "claude":    try? ClaudePermissionHook.installForClaude()
            case "qoder":     try? ClaudePermissionHook.installForQoder()
            case "qoderwork": try? ClaudePermissionHook.installForQoderWork()
            case "cursor":    try? ClaudePermissionHook.installForCursor()
            case "codex":
                try? ClaudePermissionHook.installForCodex()
                Task { await CodexAppServerClient.shared.start() }
            default:          break  // unknown provider id — ignore
            }
        }
        for providerId in removed {
            ClaudePermissionHook.uninstall(providerId: providerId)
            if providerId == "codex" {
                Task { await CodexAppServerClient.shared.stop() }
            }
        }
    }

    private func installController(for mode: CoveSettings.DisplayMode, viewModel: CoveViewModel) {
        let new: CoveModeWindowController
        switch mode {
        case .pet:   new = PetWindowController(viewModel: viewModel)
        case .notch: new = NotchWindowController(viewModel: viewModel)
        }
        new.showWindow()
        controller = new
    }

    private func swapForCurrentMode() {
        guard let viewModel else { return }
        let oldController = controller
        let newMode = CoveSettings.shared.displayMode
        let oldMode: CoveSettings.DisplayMode = (oldController is PetWindowController) ? .pet : .notch
        guard oldMode != newMode else { return }

        let duration = ModeTransition.duration(from: oldMode, to: newMode)

        // 1. Mark transition start: disables Picker (via ModeTransitionState) and
        //    causes the active controller's hover detector to ignore events.
        ModeTransitionState.shared.isTransitioning = true
        viewModel.modeTransitionInProgress = true

        // 2. Old panel fades out (first half), then we close it and install the
        //    new controller with its panel fading in (second half). Splitting
        //    the duration keeps the cross-controller swap inside the spec
        //    budget (pet→notch 540ms / notch→pet 480ms).
        oldController?.handleDisplayModeWillChange()
        if let oldPanel = oldController?.panel {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = duration / 2
                ctx.allowsImplicitAnimation = true
                oldPanel.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    oldController?.close()
                    self.controller = nil
                    self.installControllerWithFadeIn(for: newMode, viewModel: viewModel, duration: duration / 2)
                }
            }
        } else {
            // First-swap-with-no-prior-panel safety net: setup() always installs
            // a controller before any swap can fire, so this branch should be
            // unreachable. Kept defensive in case a future entry point swaps
            // before setup completes.
            installControllerWithFadeIn(for: newMode, viewModel: viewModel, duration: duration)
        }
    }

    private func installControllerWithFadeIn(
        for mode: CoveSettings.DisplayMode,
        viewModel: CoveViewModel,
        duration: TimeInterval
    ) {
        let new: CoveModeWindowController
        switch mode {
        case .pet:   new = PetWindowController(viewModel: viewModel)
        case .notch: new = NotchWindowController(viewModel: viewModel)
        }
        // Seed alpha 0 before showWindow so the fade-in starts from invisible.
        new.panel?.alphaValue = 0
        new.showWindow()
        controller = new

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.allowsImplicitAnimation = true
            new.panel?.animator().alphaValue = 1
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                ModeTransitionState.shared.isTransitioning = false
                self?.viewModel?.modeTransitionInProgress = false
            }
        }
    }

    /// Called from AppDelegate when the workspace wakes from sleep. Forces the
    /// notch back to closed and short-circuits any hover events that may have
    /// queued up while the system was asleep.
    func handleWake() {
        guard let viewModel else { return }
        if viewModel.notchStatus != .closed {
            viewModel.notchStatus = .closed
        }
        if let notchController = controller as? NotchWindowController {
            notchController.handleWake()
        }
    }
}
