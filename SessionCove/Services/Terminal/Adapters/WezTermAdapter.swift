import Foundation

/// WezTerm — focus + launch via the `wezterm cli` mux interface.
///
/// `wezterm cli list --format json` returns one entry per pane including the
/// pane's `tty_name` (e.g. `/dev/ttys003`). When we find a match we call
/// `wezterm cli activate-pane --pane-id N` and then `osascript activate` to
/// bring WezTerm forward; if the GUI isn't running yet we fall through and
/// `launch` spawns a fresh one.
struct WezTermAdapter: TerminalAdapter {
    let kind: TerminalKind = .wezterm

    var binaryPath: String {
        let candidates = [
            kind.defaultBinaryPath ?? "",
            "/usr/local/bin/wezterm",
            "/Applications/WezTerm.app/Contents/MacOS/wezterm"
        ]
        for path in candidates where !path.isEmpty {
            if TerminalAdapterHelpers.isExecutablePresent(path) {
                return path
            }
        }
        return kind.defaultBinaryPath ?? "/opt/homebrew/bin/wezterm"
    }

    var isInstalled: Bool {
        if TerminalAdapterHelpers.isAppInstalled(bundleID: kind.bundleID) { return true }
        return TerminalAdapterHelpers.isExecutablePresent(binaryPath)
    }

    func focusSession(tty: String) -> Bool {
        let fullTTY = TerminalAdapterHelpers.fullTTY(tty)

        let listResult: TerminalAdapterHelpers.ProcessOutput
        do {
            listResult = try TerminalAdapterHelpers.runProcess(
                binaryPath,
                arguments: ["cli", "list", "--format", "json"],
                kind: kind
            )
        } catch {
            print("[WezTermAdapter] cli list failed: \(error)")
            return false
        }
        guard listResult.didSucceed,
              let data = listResult.stdout.data(using: .utf8),
              let panes = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            return false
        }

        guard let paneID = panes.compactMap({ pane -> Int? in
            // wezterm prints fields like "tty_name": "/dev/ttys004" (or null).
            if let name = pane["tty_name"] as? String, name == fullTTY,
               let id = pane["pane_id"] as? Int {
                return id
            }
            return nil
        }).first else {
            return false
        }

        let activate = (try? TerminalAdapterHelpers.runProcess(
            binaryPath,
            arguments: ["cli", "activate-pane", "--pane-id", String(paneID)],
            kind: kind
        ))?.didSucceed ?? false

        if !activate { return false }

        // Bring WezTerm GUI to front (cli activate-pane only handles intra-app).
        let activateScript = """
        tell application "WezTerm" to activate
        """
        _ = TerminalAdapterHelpers.appleScriptResult(activateScript)
        return true
    }

    func launch(command: String, cwd: String) throws {
        // Prefer the mux-aware `cli spawn` so the new window joins any
        // existing wezterm GUI; fall back to `start` when no GUI is up
        // (cli spawn fails with "no running wezterm-gui").
        let spawnArgs = [
            "cli", "spawn",
            "--new-window",
            "--cwd", cwd,
            "--", "bash", "-c", command
        ]
        let spawn: TerminalAdapterHelpers.ProcessOutput
        do {
            spawn = try TerminalAdapterHelpers.runProcess(
                binaryPath,
                arguments: spawnArgs,
                kind: kind
            )
        } catch {
            // spawn failed at process level — fall through to `start`.
            spawn = TerminalAdapterHelpers.ProcessOutput(exitStatus: -1, stdout: "", stderr: "\(error)")
        }
        if spawn.didSucceed { return }

        // Fallback: launch a fresh GUI window with the command.
        let startArgs = [
            "start",
            "--cwd", cwd,
            "--", "bash", "-c", command
        ]
        let start = try TerminalAdapterHelpers.runProcess(
            binaryPath,
            arguments: startArgs,
            kind: kind
        )

        if !start.didSucceed {
            throw TerminalAdapterError.processFailed(
                kind,
                "wezterm start exit \(start.exitStatus): \(start.stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
            )
        }
    }
}
