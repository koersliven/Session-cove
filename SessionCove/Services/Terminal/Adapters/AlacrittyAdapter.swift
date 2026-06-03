import Foundation

/// Alacritty — launch only. No scripting bridge for focusing existing TTYs.
/// New windows go through the `alacritty` CLI directly.
struct AlacrittyAdapter: TerminalAdapter {
    let kind: TerminalKind = .alacritty

    /// Resolve the binary path. Honours `alacritty` in `$PATH` (homebrew
    /// install location) before falling back to the bundled binary inside
    /// `/Applications/Alacritty.app`.
    var binaryPath: String {
        let candidates = [
            kind.defaultBinaryPath ?? "",
            "/usr/local/bin/alacritty",
            "/Applications/Alacritty.app/Contents/MacOS/alacritty"
        ]
        for path in candidates where !path.isEmpty {
            if TerminalAdapterHelpers.isExecutablePresent(path) {
                return path
            }
        }
        return kind.defaultBinaryPath ?? "/opt/homebrew/bin/alacritty"
    }

    var isInstalled: Bool {
        if TerminalAdapterHelpers.isAppInstalled(bundleID: kind.bundleID) { return true }
        return TerminalAdapterHelpers.isExecutablePresent(binaryPath)
    }

    func focusSession(tty: String) -> Bool {
        // Alacritty has no per-tab focus API (and `--socket` is opt-in
        // via a patched build only). Activate the running app so its
        // window comes to the foreground; the user picks the right tab
        // themselves. Returns false when Alacritty isn't running, which
        // lets the resumer try the next adapter.
        TerminalAdapterHelpers.activateRunningApp(bundleID: kind.bundleID)
    }

    func launch(command: String, cwd: String) throws {
        // `; exec bash` keeps the window open after the command exits so the
        // user can read the prompt rather than seeing the window vanish.
        let inner = "\(command); exec bash"
        let arguments = [
            "--working-directory", cwd,
            "-e", "bash", "-c", inner
        ]

        let result = try TerminalAdapterHelpers.runProcess(
            binaryPath,
            arguments: arguments,
            kind: kind
        )

        if !result.didSucceed {
            throw TerminalAdapterError.processFailed(
                kind,
                "alacritty exit \(result.exitStatus): \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
            )
        }
    }
}
