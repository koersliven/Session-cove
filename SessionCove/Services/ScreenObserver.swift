import AppKit

/// Observes display configuration changes (lid open/close, monitor plug/unplug,
/// resolution change, scale change) and notifies subscribers.
/// PR 3 uses this to reposition the notch panel when the user changes screens.
@MainActor
final class ScreenObserver {
    static let shared = ScreenObserver()

    private var observers: [UUID: () -> Void] = [:]
    private var notificationToken: NSObjectProtocol?

    private init() {
        notificationToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // queue: .main guarantees main-thread delivery, but the closure
            // signature is nonisolated — bridge with assumeIsolated so we can
            // call back into MainActor-isolated state without an extra hop.
            MainActor.assumeIsolated {
                self?.observers.values.forEach { $0() }
            }
        }
    }

    deinit {
        if let token = notificationToken {
            NotificationCenter.default.removeObserver(token)
        }
    }

    /// Register a callback. Returns a token; pass to `unsubscribe(_:)` to remove.
    @discardableResult
    func subscribe(_ callback: @escaping () -> Void) -> UUID {
        let id = UUID()
        observers[id] = callback
        return id
    }

    func unsubscribe(_ id: UUID) {
        observers.removeValue(forKey: id)
    }
}
