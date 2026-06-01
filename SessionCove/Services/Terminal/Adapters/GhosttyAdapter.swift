import Foundation

/// Ghostty — launch only. AppleScript has no `do script` equivalent for
/// Ghostty, so `focusSession` always returns false to trigger the next
/// adapter or `launch` fallback. New windows go through `open -na`.
struct GhosttyAdapter: TerminalAdapter {
    let kind: TerminalKind = .ghostty

    var isInstalled: Bool {
        TerminalAdapterHelpers.isAppInstalled(bundleID: kind.bundleID)
    }

    func focusSession(tty: String) -> Bool {
        // Ghostty exposes no scripting bridge for command injection.
        false
    }

    func launch(command: String, cwd: String) throws {
        // `open -na Ghostty --args ... -e bash -c "<cmd>"` keeps both the
        // working directory honoured and lets us run arbitrary shell pipelines.
        // We pass the original `command` through `bash -c` rather than relying
        // on Ghostty's `-e` to splat tokens, since our caller usually composes
        // a "cd && claude --resume <id>" string.
        let arguments = [
            "-na", "Ghostty",
            "--args",
            "--working-directory=\(cwd)",
            "-e", "bash", "-c", command
        ]

        let result = try TerminalAdapterHelpers.runProcess(
            "/usr/bin/open",
            arguments: arguments,
            kind: kind
        )

        if !result.didSucceed {
            throw TerminalAdapterError.processFailed(
                kind,
                "open exit \(result.exitStatus): \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
            )
        }
    }
}
