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
        // Warp does not expose a scripting bridge for focusing a specific
        // tty/session. Always fall through.
        false
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
