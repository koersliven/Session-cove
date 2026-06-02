import AppKit
import SwiftUI

@MainActor
final class NotchWindowController: NSObject, CoveModeWindowController {
    let viewModel: CoveViewModel
    private(set) var panel: CovePanel?
    private var hostingView: PassThroughHostingView<CoveNotchView>?
    private var screenObserverToken: UUID?
    private var fullscreenToken: UUID?
    private var isClosing = false

    private let hoverDetector = NotchHoverDetector()
    private var outsideClickMonitor: Any?
    private var rightClickMonitor: Any?
    private var rightClickLocalMonitor: Any?
    /// Direct activeSpaceDidChange listener for "Mission Control / Space switch
    /// → instant close". FullscreenAppDetector also subscribes to the same
    /// notification but only updates `isFullscreen`; we need a separate hook to
    /// hard-snap the notch closed before the system's space-transition snapshot
    /// captures a half-animated panel. PR 6.T edge case 1.
    private var spaceChangeObserver: NSObjectProtocol?

    /// Records the mode we should restore to when a permission popping
    /// interruption ends. PR 4 declares this; PR 5/6 wires the full
    /// popping → restore flow per spec rows 198–200.
    private var modeBeforePopping: NotchStatus?

    init(viewModel: CoveViewModel) {
        self.viewModel = viewModel
        super.init()

        // Pick the screen the user is actively looking at (mouse pointer wins),
        // falling back to key-window screen → builtin → any. PR 6.T edge case 2:
        // multi-monitor users on the external display shouldn't see the notch
        // glued to the laptop's internal screen.
        guard let screen = currentScreen() else { return }

        let panelFrame = NotchPlacementStrategy.panelFrame(for: screen)
        let p = CovePanel(contentRect: panelFrame)
        // Closed-state default: full passthrough so the menu bar (clock, WiFi…)
        // remains clickable behind the notch panel.
        p.ignoresMouseEvents = true
        self.panel = p

        let hosting = PassThroughHostingView(rootView: CoveNotchView(viewModel: viewModel))
        hosting.frame = NSRect(origin: .zero, size: panelFrame.size)
        hosting.layer?.backgroundColor = .clear
        hosting.hitTestRectProvider = { [] }
        p.contentView = hosting
        self.hostingView = hosting

        screenObserverToken = ScreenObserver.shared.subscribe { [weak self] in
            self?.repositionForScreenChange()
        }

        // Hover wiring: closed ↔ peeking driven by sustained hover.
        // Click handling that escalates peeking → opened lives in CoveNotchView
        // via .onTapGesture (the panel's hit test covers the content area when
        // peeking/opened, so SwiftUI gestures fire normally there).
        hoverDetector.onSustainedEnter = { [weak self] in
            guard let self else { return }
            print("[Hover] sustainedEnter — currentStatus=\(self.viewModel.notchStatus)")
            if self.viewModel.notchStatus == .closed {
                self.viewModel.notchStatus = .peeking
            }
        }
        hoverDetector.onSustainedExit = { [weak self] in
            guard let self else { return }
            print("[Hover] sustainedExit — currentStatus=\(self.viewModel.notchStatus)")
            if self.viewModel.notchStatus == .peeking {
                self.viewModel.notchStatus = .closed
            }
        }
        hoverDetector.setNotchScreenRect(closedHoverZone(on: screen))

        // Click outside the panel while opened collapses back to closed.
        // Note: PetWindowController has its own global monitor for the .pet
        // mode — we live alongside it; when WindowManager swaps modes, only
        // one controller is active at a time so monitors don't conflict.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            if let event = NSApp.currentEvent, MouseEventReplay.isReplayed(event) { return }
            MainActor.assumeIsolated {
                guard let self, let screen = self.currentScreen() else { return }
                let loc = NSEvent.mouseLocation
                // Panel is fullWidth × 750 always, but only the visible notch
                // graphic should count as "inside" — clicks on the surrounding
                // transparent panel area should still close the opened notch.
                let visible = self.visibleNotchScreenRect(
                    for: self.viewModel.notchStatus,
                    on: screen,
                    kind: self.viewModel.pendingHookRequest?.kind
                )
                if !visible.contains(loc) {
                    if self.viewModel.notchStatus == .opened {
                        print("[OutsideClick] mouseDown outside notch while opened → forcing closed (loc=\(loc))")
                        self.viewModel.notchStatus = .closed
                    } else if self.viewModel.notchStatus == .popping {
                        print("[OutsideClick] mouseDown outside notch while popping — IGNORED (force-decision policy) loc=\(loc)")
                    }
                }
            }
        }

        // Right-click anywhere on the notch panel pops the StatusMenu so users
        // can switch back to .pet mode (or hit Settings / Quit) without having
        // to find the menu bar icon. We need BOTH monitors:
        //   - GLOBAL: closed state has `ignoresMouseEvents = true`, so the click
        //     is routed to whichever app sits behind the notch (menu bar /
        //     desktop). Global monitors only fire for events delivered to other
        //     apps, which is exactly this case.
        //   - LOCAL: peeking/opened state has `ignoresMouseEvents = false`, so
        //     our panel intercepts the event and global never fires. Local
        //     monitors run inside the current app and let us swallow the event
        //     by returning nil so the panel's default handling doesn't re-fire.
        // Two-finger tap (secondary click) routes through the same NSEvent path
        // as a real right-click, so this covers both gestures.
        rightClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.rightMouseDown]) { [weak self] _ in
            if let event = NSApp.currentEvent, MouseEventReplay.isReplayed(event) { return }
            MainActor.assumeIsolated {
                guard let self, let screen = self.currentScreen() else { return }
                let loc = NSEvent.mouseLocation
                let visible = self.visibleNotchScreenRect(
                    for: self.viewModel.notchStatus,
                    on: screen,
                    kind: self.viewModel.pendingHookRequest?.kind
                )
                guard visible.contains(loc) else { return }
                let menu = StatusMenu.build(target: nil)
                menu.popUp(positioning: nil, at: loc, in: nil)
            }
        }
        rightClickLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown]) { [weak self] event -> NSEvent? in
            MainActor.assumeIsolated {
                if MouseEventReplay.isReplayed(event) { return event }
                guard let self, let screen = self.currentScreen() else { return event }
                let loc = NSEvent.mouseLocation
                let visible = self.visibleNotchScreenRect(
                    for: self.viewModel.notchStatus,
                    on: screen,
                    kind: self.viewModel.pendingHookRequest?.kind
                )
                guard visible.contains(loc) else { return event }
                let menu = StatusMenu.build(target: nil)
                menu.popUp(positioning: nil, at: loc, in: nil)
                return nil
            }
        }

        observeNotchStatus()
        observePendingHookRequest()
        applyNotchStatus(viewModel.notchStatus)

        // Fullscreen-app gating: hide the notch panel while a fullscreen app
        // is in front (e.g. Keynote, Mission Control fullscreen window). The
        // initial callback fires synchronously from subscribe(), so this also
        // handles "launched while a fullscreen app is already focused".
        // Subscriber closure must hop to MainActor because the typealias is
        // a non-isolated `@escaping (Bool) -> Void`; FullscreenAppDetector
        // dispatches it on the main queue, so assumeIsolated is sound.
        fullscreenToken = FullscreenAppDetector.shared.subscribe { [weak self] isFullscreen in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel else { return }
                let activeScreen = self.currentScreen() ?? NSScreen.main
                let hasPhysicalNotch = (activeScreen?.notchMetrics != nil)

                if isFullscreen {
                    if hasPhysicalNotch {
                        // Physical notch: alpha-hide the SwiftUI notch graphic so
                        // the system's native notch + fullscreen menu auto-show
                        // takes over. PR 6.T edge case 4 (notch path).
                        panel.animator().alphaValue = 0
                    } else {
                        // No physical notch: slide the panel up so the closed
                        // notch graphic exits the screen, leaving an 8pt hover
                        // strip at the top edge for the user to trigger reveal.
                        // closedNotchHeight (32) mirrors `closedHoverZone.hotH`
                        // — keep them in sync. PR 6.T edge case 4 (no-notch path).
                        let closedNotchHeight: CGFloat = 32
                        let slideUp = closedNotchHeight + 12 - 8
                        var f = panel.frame
                        f.origin.y += slideUp
                        panel.animator().setFrame(f, display: true)
                        panel.animator().alphaValue = 1
                    }
                } else {
                    // Exit fullscreen: restore alpha and snap the panel back to
                    // its canonical fullWidth × 750 frame (in case slideUp shifted
                    // it). Constant-panel architecture means applyNotchStatus
                    // doesn't reset frames itself, so we do it explicitly here.
                    panel.animator().alphaValue = 1
                    if let screen = self.currentScreen() {
                        let canonical = NotchPlacementStrategy.panelFrame(for: screen)
                        panel.animator().setFrame(canonical, display: true)
                    }
                    self.applyNotchStatus(self.viewModel.notchStatus)
                }
            }
        }

        // Mission Control / Space switch: snap closed instantly. PR 6.T edge
        // case 1. FullscreenAppDetector listens to the same notification but
        // only updates `isFullscreen`; we need our own observer to force a
        // close before the system captures a space-transition snapshot of a
        // half-animated panel. Hard-set status (no SwiftUI animation) — during
        // the space transition the panel content stops rendering, so a slow
        // animation just freezes the last frame.
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.viewModel.notchStatus != .closed {
                    print("[SpaceChange] active space changed — forcing closed (was \(self.viewModel.notchStatus))")
                    self.hoverDetector.cancelPending()
                    self.hoverDetector.isAnimating = true
                    self.viewModel.notchStatus = .closed
                }
            }
        }
    }

    func showWindow() {
        panel?.orderFrontRegardless()
    }

    /// Idempotent teardown — swap, teardown, deinit may all race; the guard
    /// keeps the cleanup deterministic and avoids double-removeMonitor /
    /// double-unsubscribe.
    func close() {
        guard !isClosing else { return }
        isClosing = true
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
        if let monitor = rightClickMonitor {
            NSEvent.removeMonitor(monitor)
            rightClickMonitor = nil
        }
        if let monitor = rightClickLocalMonitor {
            NSEvent.removeMonitor(monitor)
            rightClickLocalMonitor = nil
        }
        if let token = screenObserverToken {
            ScreenObserver.shared.unsubscribe(token)
            screenObserverToken = nil
        }
        if let token = fullscreenToken {
            FullscreenAppDetector.shared.unsubscribe(token)
            fullscreenToken = nil
        }
        if let obs = spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            spaceChangeObserver = nil
        }
        hoverDetector.cancelPending()
        panel?.orderOut(nil)
    }

    func handleDisplayModeWillChange() {
        // Soft-stop: cancel pending hover and freeze the detector. Actual
        // cleanup (orderOut + observer detach) waits until the swap's fade-out
        // completes; WindowManager calls close() in the animation completion.
        hoverDetector.cancelPending()
        hoverDetector.isAnimating = true
        if let token = screenObserverToken {
            ScreenObserver.shared.unsubscribe(token)
            screenObserverToken = nil
        }
    }

    /// Called from WindowManager.handleWake when the workspace wakes. Cancels
    /// any in-flight hover work and briefly suppresses new hover events so a
    /// mouse parked over the notch zone during sleep doesn't immediately fire
    /// a peek while SwiftUI is still re-rendering the closed state.
    func handleWake() {
        hoverDetector.cancelPending()
        hoverDetector.isAnimating = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            MainActor.assumeIsolated {
                self?.hoverDetector.isAnimating = false
            }
        }
    }

    private func repositionForScreenChange() {
        // 220ms easeOut transparency cross-fade around the reposition. Without
        // it the panel "flies" across the desktop on lid-open / monitor swap.
        // Split into two 110ms halves: fade-out → re-apply geometry → fade-in.
        // PR 6.T edge case 3.
        guard let panel = panel else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.110
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Repin to whichever screen is now active. With the constant-panel
                // architecture, applyNotchStatus no longer touches the panel
                // frame, so we set it explicitly for the new screen here.
                if let screen = self.currentScreen() {
                    let canonical = NotchPlacementStrategy.panelFrame(for: screen)
                    self.panel?.setFrame(canonical, display: true, animate: false)
                    self.hostingView?.frame = NSRect(origin: .zero, size: canonical.size)
                }
                self.applyNotchStatus(self.viewModel.notchStatus)
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.110
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    ctx.allowsImplicitAnimation = true
                    self.panel?.animator().alphaValue = 1
                }
            }
        }
    }

    // MARK: - Status machine

    /// Subscribe to notchStatus mutations on the @Observable viewModel.
    /// Observation is one-shot, so we re-subscribe after each fire.
    /// The Task hop ensures we read the *new* value (onChange runs willSet-style).
    private func observeNotchStatus() {
        withObservationTracking {
            _ = viewModel.notchStatus
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                print("[NotchStatus] changed → \(self.viewModel.notchStatus) (pending=\(self.viewModel.pendingHookRequest?.id ?? "nil"))")
                self.applyNotchStatus(self.viewModel.notchStatus)
                self.observeNotchStatus()
            }
        }
    }

    /// Bridge `viewModel.pendingHookRequest` ↔ `notchStatus = .popping`.
    /// Plan stage 1 wires the popping path the previous PRs declared but
    /// never actually triggered. Same one-shot tracking pattern as
    /// `observeNotchStatus` — re-subscribe after each fire.
    ///
    /// - pending arrives while not popping → save current status to
    ///   `modeBeforePopping`, force `.popping`.
    /// - pending clears while popping → restore `modeBeforePopping ?? .closed`.
    /// `spaceChangeObserver` resets to `.closed` on space switch but keeps the
    /// pending request alive in the viewModel; when the user returns, this
    /// observer re-fires and pops the panel back open.
    private func observePendingHookRequest() {
        // Step 1 — synchronously reconcile against the *current* value.
        // withObservationTracking only fires on subsequent changes, so a
        // pending that was already set before this controller existed
        // (e.g. hookPolling found one between WindowManager.setup() and
        // installController()) would never trigger popping. The visible
        // bug: notch status dot lit yellow but the popping panel never
        // appeared. Reconcile-then-track closes that race.
        reconcilePoppingForPendingHookRequest()

        withObservationTracking {
            _ = viewModel.pendingHookRequest
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.reconcilePoppingForPendingHookRequest()
                self.observePendingHookRequest()
            }
        }
    }

    private func reconcilePoppingForPendingHookRequest() {
        let pending = viewModel.pendingHookRequest
        let status = viewModel.notchStatus
        print("[NotchPopping] reconcile — pending=\(pending?.id ?? "nil") status=\(status) modeBefore=\(String(describing: modeBeforePopping))")
        if pending != nil, status != .popping {
            modeBeforePopping = status
            viewModel.notchStatus = .popping
            print("[NotchPopping] → popping (saved modeBeforePopping=\(status))")
        } else if pending == nil, status == .popping {
            let target = modeBeforePopping ?? .closed
            viewModel.notchStatus = target
            modeBeforePopping = nil
            print("[NotchPopping] ← restored from popping → \(target)")
        }
    }

    func applyNotchStatus(_ status: NotchStatus) {
        guard let panel, let screen = currentScreen() else { return }

        // Cancel any in-flight debounced enter/exit before raising the
        // animation gate. Without this a stale `pendingExitWork` fired during
        // a programmatic status change (e.g. island tap → opened) would
        // immediately retarget the spring back to closed mid-flight.
        hoverDetector.cancelPending()
        hoverDetector.isAnimating = true

        // Constant-panel architecture: the NSPanel stays at fullWidth × 750 in
        // every state. All visual morphing happens inside SwiftUI via
        // `clipShape(NotchShape)` + `.frame(width:height:)` interpolation in
        // CoveNotchView. This eliminates the screen-top-left flash that
        // happened when AppKit redrew SwiftUI's outgoing snapshot at the
        // newly-resized panel's origin.
        switch status {
        case .closed:
            // Full passthrough: menu bar receives clicks behind the notch.
            panel.ignoresMouseEvents = true
            hostingView?.hitTestRectProvider = { [] }
            hoverDetector.setNotchScreenRect(closedHoverZone(on: screen))
        case .peeking, .opened, .popping:
            // Panel intercepts events only inside the visible notch graphic;
            // the surrounding transparent panel area passes through. Hover hot
            // zone matches the visible-notch screen rect so moving inside the
            // visible content doesn't trigger a spurious "exit".
            panel.ignoresMouseEvents = false
            // The hit-test closure reads `kind` lazily so a popping panel that
            // morphs from approval (120pt) to question (360pt) — e.g. one
            // request resolves and another arrives — still matches the latest
            // SwiftUI height without needing a fresh applyNotchStatus call.
            hostingView?.hitTestRectProvider = { [weak self] in
                guard let self else { return [] }
                let kind = self.viewModel.pendingHookRequest?.kind
                return [self.visibleNotchPanelRect(for: status, kind: kind)]
            }
            hoverDetector.setNotchScreenRect(
                visibleNotchScreenRect(
                    for: status,
                    on: screen,
                    kind: viewModel.pendingHookRequest?.kind
                )
            )
        }

        switch status {
        case .opened:
            CoveSoundManager.shared.play(.waterSplash, volumeOverride: 0.25)  // -12 dB
        case .closed:
            CoveSoundManager.shared.play(.bubblePop, volumeOverride: 0.13)    // -18 dB
        case .peeking, .popping:
            break
        }

        // Clear isAnimating + force a hover re-evaluation. 600ms matches the
        // SwiftUI spring's flight time (response 0.42 ≈ 1.5× = 630ms). Earlier
        // gate clears (e.g. 200ms) leave hoverDetector responding to cursor
        // wobble while the spring is still mid-flight, causing the "伸到一半又
        // 缩回" jitter. The re-evaluation is essential: if cursor parked inside
        // the new hot zone during the gate, no mouseMoved would fire post-gate.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.60) { [weak self] in
            MainActor.assumeIsolated {
                self?.hoverDetector.clearAnimatingAndReevaluate()
            }
        }
    }

    // MARK: - Geometry

    /// Visible notch graphic dimensions for each state. The panel itself is
    /// always fullWidth × 750; these sizes describe the morphing black-clipped
    /// container inside SwiftUI. Mirror the values in CoveNotchView so the
    /// hit-test rects stay in lockstep with the visual. `kind` only matters in
    /// `.popping`: question kind needs ~360pt of vertical space for the
    /// ScrollView + options; legacy approval still uses the compact 120pt strip.
    private func visibleNotchSize(for status: NotchStatus, kind: HookRequestKind?) -> CGSize {
        switch status {
        case .closed: return CGSize(width: 224, height: 32)
        case .peeking: return CGSize(width: 480, height: 220)
        case .opened: return CGSize(width: 600, height: 480)
        case .popping:
            // Mirror CoveNotchView.notchHeight: question 360 / completion 120 /
            // approval 120 collapsed or 240 expanded. approvalExpanded read
            // lazily via the closure caller (visibleNotchScreenRect / hit test
            // closure) so a chevron toggle without notchStatus change still
            // updates the hit-test rect.
            let height: CGFloat = {
                switch kind {
                case .question: return 360
                case .completion: return 120
                case .approval, .none:
                    return viewModel.approvalExpanded ? 240 : 120
                }
            }()
            return CGSize(width: 480, height: height)
        }
    }

    /// Visible notch rect in panel-local (bottom-left origin) coords, suitable
    /// for `PassThroughHostingView.hitTestRectProvider`. Top-aligned within
    /// the panel; horizontally centered.
    private func visibleNotchPanelRect(for status: NotchStatus, kind: HookRequestKind?) -> NSRect {
        guard let panel = panel else { return .zero }
        let size = visibleNotchSize(for: status, kind: kind)
        return NSRect(
            x: panel.frame.width / 2 - size.width / 2,
            y: panel.frame.height - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// Visible notch rect in screen coords. Used by hover detector +
    /// outside-click + right-click handlers so they only react to the actual
    /// visible notch graphic, not the invisible fullWidth panel surrounding it.
    private func visibleNotchScreenRect(for status: NotchStatus, on screen: NSScreen, kind: HookRequestKind?) -> NSRect {
        let size = visibleNotchSize(for: status, kind: kind)
        return NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// Hot zone for closed state: the area directly under the physical notch
    /// in screen coordinates. Aggressive sizing — width is `notch + 100pt` on
    /// each-side-bias-friendly basis (so off-center hovers near the menu bar
    /// items still trigger), height 44pt (vs the 32pt visual notch) for a
    /// forgiving vertical band. Total ≈ 320×44 on a 14" MacBook Pro.
    private func closedHoverZone(on screen: NSScreen) -> NSRect {
        let metrics = screen.notchMetrics ?? .fallback
        let baseW = max(metrics.width, ScreenNotchMetrics.fallback.width)
        let hotW = max(baseW + 100, 320)
        let hotH: CGFloat = 44
        return NSRect(
            x: screen.frame.midX - hotW / 2,
            y: screen.frame.maxY - hotH,
            width: hotW,
            height: hotH
        )
    }

    /// Screen the user is currently looking at: prefer the screen containing
    /// the mouse pointer, then fall back to NSScreen.main (key window screen),
    /// then builtin, then any screen. PR 6.T edge case 2 — replaces the
    /// "always builtin" assumption from PR 5 so multi-monitor users see the
    /// notch on whichever display they're actively interacting with.
    private func currentScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        if let s = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
            return s
        }
        return NSScreen.main ?? NSScreen.builtin ?? NSScreen.screens.first
    }

    deinit {
        // ScreenObserver and NSEvent monitor removal are safe on any thread,
        // but reading our @MainActor stored properties requires isolation.
        MainActor.assumeIsolated {
            if let token = screenObserverToken {
                ScreenObserver.shared.unsubscribe(token)
            }
            if let monitor = outsideClickMonitor {
                NSEvent.removeMonitor(monitor)
            }
            if let monitor = rightClickMonitor {
                NSEvent.removeMonitor(monitor)
            }
            if let monitor = rightClickLocalMonitor {
                NSEvent.removeMonitor(monitor)
            }
            if let token = fullscreenToken {
                FullscreenAppDetector.shared.unsubscribe(token)
            }
            if let obs = spaceChangeObserver {
                NSWorkspace.shared.notificationCenter.removeObserver(obs)
            }
        }
    }
}
