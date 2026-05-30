import AppKit

/// Tracks mouse position over the notch hot zone and emits `enter` / `exit`
/// events with debouncing to prevent flicker when the user grazes the area.
///
/// Why debounce: rapid hover-in-out (5/sec) should NOT cause visual flicker —
/// only sustained hover ≥240ms expands the notch, only sustained absence ≥320ms
/// collapses it. The hot zone is updated by the controller as panel geometry
/// changes (e.g. it grows to cover the full peeking panel so hover-into-content
/// doesn't trigger an "exit").
@MainActor
final class NotchHoverDetector {
    /// Hot zone (in screen coordinates) the detector treats as "inside".
    /// Updated via `setNotchScreenRect(_:)` when the screen or notch geometry
    /// changes (e.g. status transitions from closed → peeking).
    private var notchScreenRect: NSRect = .zero
    private var localMonitor: Any?
    private var globalMonitor: Any?

    /// Fires after the user has been continuously inside the hot zone for
    /// `enterDebounce` seconds.
    var onSustainedEnter: (() -> Void)?
    /// Fires after the user has been continuously outside the hot zone for
    /// `exitDebounce` seconds.
    var onSustainedExit: (() -> Void)?

    /// True while a state-machine transition is animating; we ignore hover
    /// events to prevent jitter (e.g. mid-spring overshoot bouncing the
    /// pointer in/out of the hot zone).
    var isAnimating: Bool = false

    private var pendingEnterWork: DispatchWorkItem?
    private var pendingExitWork: DispatchWorkItem?
    private var insideZone: Bool = false

    private static let enterDebounce: TimeInterval = 0.240
    private static let exitDebounce: TimeInterval = 0.320

    init() {
        // mouseMoved is delivered to .local for our own app, .global for events
        // routed elsewhere. We need both because the notch panel uses
        // ignoresMouseEvents=true while .closed — the app would never see the
        // event locally. NSEvent monitors fire on the main run loop, so
        // MainActor.assumeIsolated is a synchronous bridge with no extra hop.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handle(screenLocation: NSEvent.mouseLocation)
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handle(screenLocation: NSEvent.mouseLocation)
            }
        }
    }

    deinit {
        // NSEvent.removeMonitor is thread-safe, but accessing our @MainActor
        // properties requires actor isolation. Ditto DispatchWorkItem.cancel().
        MainActor.assumeIsolated {
            if let m = localMonitor { NSEvent.removeMonitor(m) }
            if let m = globalMonitor { NSEvent.removeMonitor(m) }
            pendingEnterWork?.cancel()
            pendingExitWork?.cancel()
        }
    }

    func setNotchScreenRect(_ rect: NSRect) {
        notchScreenRect = rect
    }

    /// Cancel any pending debounced enter/exit. Call when the controller
    /// programmatically changes status (e.g. via click) so the next hover
    /// won't trigger a stale transition.
    func cancelPending() {
        pendingEnterWork?.cancel()
        pendingExitWork?.cancel()
        pendingEnterWork = nil
        pendingExitWork = nil
    }

    private func handle(screenLocation: NSPoint) {
        guard !isAnimating else { return }
        let nowInside = notchScreenRect.contains(screenLocation)
        guard nowInside != insideZone else { return }
        insideZone = nowInside

        if nowInside {
            pendingExitWork?.cancel()
            pendingExitWork = nil
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    self?.onSustainedEnter?()
                }
            }
            pendingEnterWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.enterDebounce, execute: work)
        } else {
            pendingEnterWork?.cancel()
            pendingEnterWork = nil
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    self?.onSustainedExit?()
                }
            }
            pendingExitWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.exitDebounce, execute: work)
        }
    }
}
