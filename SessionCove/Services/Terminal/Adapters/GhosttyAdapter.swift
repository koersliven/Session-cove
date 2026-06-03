import Foundation

/// Ghostty — half-adapted focus. Ghostty has no scripting bridge to
/// target a specific tab/tty (the upstream issue tracker has an open
/// vouch request for `+new-window` IPC via Unix-domain socket but it
/// hasn't shipped). When the ancestor of the live `claude` pid is
/// Ghostty, the best we can do is activate the Ghostty app so its
/// window comes to the foreground — the user picks the right tab
/// themselves with ⌘1/⌘2/.... Strictly better than returning false
/// and falling through to `launch`, which would spawn a fresh
/// `claude --resume` and duplicate the session.
struct GhosttyAdapter: TerminalAdapter {
    let kind: TerminalKind = .ghostty

    var isInstalled: Bool {
        TerminalAdapterHelpers.isAppInstalled(bundleID: kind.bundleID)
    }

    func focusSession(tty: String) -> Bool {
        TerminalAdapterHelpers.activateRunningApp(bundleID: kind.bundleID)
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
