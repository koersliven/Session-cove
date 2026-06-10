import AppKit
import Foundation

/// Adapter for IDE-hosted integrated terminals (VS Code, Cursor).
///
/// These are Electron apps. Their integrated terminal cannot be focused down
/// to a specific tty/tab via AppleScript the way iTerm/Terminal.app can, so
/// "focus" degrades to activating the IDE window via its bundle id — which
/// brings the user back to the window that hosts the running agent session.
/// That is strictly better than the previous behavior, where an
/// IDE-integrated-terminal session fell through every real-terminal adapter
/// and ended up spawning a brand-new iTerm/Terminal window (a duplicate,
/// detached session).
///
/// We never *launch* a fresh agent into an IDE integrated terminal — that
/// path stays with the real terminal adapters — so `launch` is unsupported
/// and `TerminalDetector.adapter(for:)` returns `nil` for these kinds,
/// keeping them out of the launch cascade.
struct IDEWindowAdapter: TerminalAdapter {
    let kind: TerminalKind

    var isInstalled: Bool {
        TerminalAdapterHelpers.isAppInstalled(bundleID: kind.bundleID)
    }

    /// Bring the IDE window to the front. The `tty` is ignored because the
    /// integrated terminal can't be addressed individually; activating the
    /// app surfaces the window the session lives in.
    func focusSession(tty: String) -> Bool {
        TerminalAdapterHelpers.activateRunningApp(bundleID: kind.bundleID)
    }

    func launch(command: String, cwd: String) throws {
        throw TerminalAdapterError.unsupportedOperation(
            kind,
            "launch into an IDE integrated terminal"
        )
    }
}
