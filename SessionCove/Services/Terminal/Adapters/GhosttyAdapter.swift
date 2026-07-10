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
        // Ghostty on macOS cannot be launched directly from the CLI; the
        // documented path is `open -na Ghostty.app --args <config flags> -e <cmd>`.
        //
        // Three correctness details the previous implementation got wrong:
        //
        //   1. `-e` MUST be the last argument group. Ghostty treats every
        //      token after `-e` as the command + its argv, so any config flag
        //      (like `--working-directory`) has to appear *before* `-e`. That
        //      ordering is preserved below.
        //   2. Running `bash -c "<cmd>"` closes the window the instant the
        //      command exits (e.g. when `claude --resume` finishes). We wrap
        //      in an interactive login shell that `cd`s into the project and
        //      then `exec`s the command, so the user lands in a live shell in
        //      the right directory — matching the iTerm / Terminal.app resume
        //      experience instead of a window that vanishes.
        //   3. `--wait-after-command=true` keeps the surface open even if the
        //      wrapped command exits abnormally, so errors stay visible.
        //
        // `cwd` is single-quote escaped before being embedded in the shell
        // string since it flows through `zsh -ilc`.
        let quotedCwd = TerminalAdapterHelpers.shellEscape(cwd)
        let shellLine = "cd \(quotedCwd) && exec \(command)"

        let arguments = [
            "-na", "Ghostty.app",
            "--args",
            "--working-directory=\(cwd)",
            "--wait-after-command=true",
            "-e", "/bin/zsh", "-ilc", shellLine
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
