import Foundation

/// Warp — excluded from v1 (per design doc). The proper integration would
/// require dropping a YAML launch configuration into
/// `~/.warp/launch_configurations/cove-<id>.yaml` and opening
/// `warp://launch/cove-<id>` — too much side effect for the first cut, and
/// Warp gives us no focus path at all.
///
/// Both methods fail safely so the upper-level resumer falls back to the
/// next adapter (typically Terminal.app).
struct WarpAdapter: TerminalAdapter {
    let kind: TerminalKind = .warp

    var isInstalled: Bool {
        TerminalAdapterHelpers.isAppInstalled(bundleID: kind.bundleID)
    }

    func focusSession(tty: String) -> Bool {
        // Warp has no per-tab focus API; activate the app so its window
        // comes to the foreground and the user picks the right tab.
        // Strictly better than falling through to a launch that would
        // duplicate the session. Returns false when Warp isn't running,
        // letting the resumer try the next adapter in the focus chain.
        TerminalAdapterHelpers.activateRunningApp(bundleID: kind.bundleID)
    }

    func launch(command: String, cwd: String) throws {
        // v1: refuse to launch into Warp. Throwing keeps the contract honest
        // (the resumer treats this as a hard failure and tries the next
        // adapter / Terminal.app fallback).
        throw TerminalAdapterError.unsupportedOperation(
            kind,
            "launch (Warp v1 placeholder — fallback to Terminal.app)"
        )
    }
}
