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
            if self.viewModel.notchStatus == .closed {
                self.viewModel.notchStatus = .peeking
            }
        }
        hoverDetector.onSustainedExit = { [weak self] in
            guard let self else { return }
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
                guard let self, let panel = self.panel else { return }
                let loc = NSEvent.mouseLocation
                if !panel.frame.contains(loc) {
                    if self.viewModel.notchStatus == .opened {
                        self.viewModel.notchStatus = .closed
                    }
                }
            }
        }

        // Right-click anywhere on the notch panel pops the StatusMenu so users
        // can switch back to .pet mode (or hit Settings / Quit) without having
        // to find the menu bar icon. Closed state is `ignoresMouseEvents=true`
        // so a panel-local view monitor would never see the event — the click
        // routes past the panel to whatever is behind. A global monitor catches
        // the event regardless and we hit-test against `panel.frame` ourselves.
        rightClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.rightMouseDown]) { [weak self] _ in
            if let event = NSApp.currentEvent, MouseEventReplay.isReplayed(event) { return }
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel else { return }
                let loc = NSEvent.mouseLocation
                guard panel.frame.contains(loc) else { return }
                let menu = StatusMenu.build(target: nil)
                menu.popUp(positioning: nil, at: loc, in: nil)
            }
        }

        observeNotchStatus()
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
                    // Exit fullscreen: restore alpha and reapply the current
                    // status so the panel frame snaps back to the canonical
                    // position for that NotchStatus.
                    panel.animator().alphaValue = 1
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
                self.applyNotchStatus(self.viewModel.notchStatus)
                self.observeNotchStatus()
            }
        }
    }

    func applyNotchStatus(_ status: NotchStatus) {
        guard let panel, let screen = currentScreen() else { return }

        hoverDetector.isAnimating = true

        let targetFrame = self.targetFrame(for: status, on: screen)
        // animate: false — AppKit's animator curve is harsh; SwiftUI animates
        // the content morph via the .animation(_, value:) modifier in CoveNotchView.
        panel.setFrame(targetFrame, display: true, animate: false)
        hostingView?.frame = NSRect(origin: .zero, size: targetFrame.size)

        switch status {
        case .closed:
            // Full passthrough: menu bar receives clicks behind the notch.
            panel.ignoresMouseEvents = true
            hostingView?.hitTestRectProvider = { [] }
            hoverDetector.setNotchScreenRect(closedHoverZone(on: screen))
        case .peeking, .opened, .popping:
            // Panel intercepts events inside its bounds; the hover hot zone
            // expands to cover the entire panel so moving inside content
            // doesn't trigger a spurious "exit".
            panel.ignoresMouseEvents = false
            hostingView?.hitTestRectProvider = { [weak self] in
                guard let bounds = self?.hostingView?.bounds else { return [] }
                return [bounds]
            }
            hoverDetector.setNotchScreenRect(panel.frame)
        }

        switch status {
        case .opened:
            CoveSoundManager.shared.play(.waterSplash, volumeOverride: 0.25)  // -12 dB
        case .closed:
            CoveSoundManager.shared.play(.bubblePop, volumeOverride: 0.13)    // -18 dB
        case .peeking, .popping:
            break
        }

        // Clear isAnimating after the longest spring duration with slack —
        // peeking → opened is 320ms per spec; 420ms gives the spring room
        // to settle before we accept hover events again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) { [weak self] in
            MainActor.assumeIsolated {
                self?.hoverDetector.isAnimating = false
            }
        }
    }

    // MARK: - Geometry

    private func targetFrame(for status: NotchStatus, on screen: NSScreen) -> NSRect {
        let frame = screen.frame
        switch status {
        case .closed:
            // PR 3 baseline: full-screen-width × 750 panel anchored top so the
            // notch graphic itself sits flush with the menu bar.
            // panelFrame(for:) already integer-ceils internally, but route
            // through ceilFrame for symmetry with the other cases.
            return ceilFrame(NotchPlacementStrategy.panelFrame(for: screen))
        case .peeking:
            let w: CGFloat = 480
            let h: CGFloat = 220
            return ceilFrame(NSRect(
                x: frame.midX - w / 2,
                y: frame.maxY - h,
                width: w,
                height: h
            ))
        case .opened, .popping:
            // Spec mentions opened height as `min(720, measured)`; measuring
            // requires a layout pass. PR 4 uses a fixed 480; PR 5 can refine.
            let w: CGFloat = 600
            let h: CGFloat = 480
            return ceilFrame(NSRect(
                x: frame.midX - w / 2,
                y: frame.maxY - h,
                width: w,
                height: h
            ))
        }
    }

    /// Snap an NSRect to integer pixels. Avoids half-pixel shimmer on Retina /
    /// fractional-DPI external displays where `frame.midX - w / 2` can return
    /// a fractional origin. PR 6.T edge case 5.
    private func ceilFrame(_ rect: NSRect) -> NSRect {
        NSRect(
            x: ceil(rect.origin.x),
            y: ceil(rect.origin.y),
            width: ceil(rect.size.width),
            height: ceil(rect.size.height)
        )
    }

    /// Hot zone for closed state: the area directly under the physical notch
    /// in screen coordinates, slightly enlarged vertically (36pt vs 32pt) for
    /// forgiving hover.
    private func closedHoverZone(on screen: NSScreen) -> NSRect {
        let metrics = screen.notchMetrics ?? .fallback
        let hotW = max(metrics.width, ScreenNotchMetrics.fallback.width)
        let hotH: CGFloat = 36
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
            if let token = fullscreenToken {
                FullscreenAppDetector.shared.unsubscribe(token)
            }
            if let obs = spaceChangeObserver {
                NSWorkspace.shared.notificationCenter.removeObserver(obs)
            }
        }
    }
}
