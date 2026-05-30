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

    /// Records the mode we should restore to when a permission popping
    /// interruption ends. PR 4 declares this; PR 5/6 wires the full
    /// popping → restore flow per spec rows 198–200.
    private var modeBeforePopping: NotchStatus?

    init(viewModel: CoveViewModel) {
        self.viewModel = viewModel
        super.init()

        guard let screen = NSScreen.builtin ?? NSScreen.main else { return }

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
                if isFullscreen {
                    // PR 5 keeps it simple: alpha 0 fully hides the notch panel
                    // when a fullscreen app is active. Spec mentions a 8pt
                    // hover-trigger strip on non-notch displays — that's
                    // earmarked for PR 6 / hover-zone tuning.
                    panel.animator().alphaValue = 0
                } else {
                    panel.animator().alphaValue = 1
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
        if let token = screenObserverToken {
            ScreenObserver.shared.unsubscribe(token)
            screenObserverToken = nil
        }
        if let token = fullscreenToken {
            FullscreenAppDetector.shared.unsubscribe(token)
            fullscreenToken = nil
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
        // Re-apply the current status so panel frame and hover zone follow
        // the new screen geometry (lid open/close, monitor change, etc.).
        applyNotchStatus(viewModel.notchStatus)
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
        guard let panel, let screen = NSScreen.builtin ?? NSScreen.main else { return }

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
            return NotchPlacementStrategy.panelFrame(for: screen)
        case .peeking:
            let w: CGFloat = 480
            let h: CGFloat = 220
            return NSRect(
                x: frame.midX - w / 2,
                y: frame.maxY - h,
                width: w,
                height: h
            )
        case .opened, .popping:
            // Spec mentions opened height as `min(720, measured)`; measuring
            // requires a layout pass. PR 4 uses a fixed 480; PR 5 can refine.
            let w: CGFloat = 600
            let h: CGFloat = 480
            return NSRect(
                x: frame.midX - w / 2,
                y: frame.maxY - h,
                width: w,
                height: h
            )
        }
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
            if let token = fullscreenToken {
                FullscreenAppDetector.shared.unsubscribe(token)
            }
        }
    }
}
