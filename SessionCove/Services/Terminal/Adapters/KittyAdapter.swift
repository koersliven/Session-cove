import Foundation

/// kitty — focus + launch via the `kitty @` remote control socket.
///
/// Focus path requires `allow_remote_control=yes` and a known socket path.
/// We hard-code the socket at `unix:/tmp/kitty-cove`; any kitty window that
/// was spawned by `launch(...)` (which appends `--listen-on`) will be visible
/// to `kitty @ ls`.
///
/// If the socket isn't reachable (no Cove-launched kitty window yet, or the
/// user disabled remote control), `focusSession` returns false and the upper
/// layer falls back to `launch`, which always succeeds for an installed kitty.
struct KittyAdapter: TerminalAdapter {
    let kind: TerminalKind = .kitty

    static let socketPath: String = "unix:/tmp/kitty-cove"

    var binaryPath: String {
        let candidates = [
            kind.defaultBinaryPath ?? "",
            "/usr/local/bin/kitty",
            "/opt/homebrew/bin/kitty"
        ]
        for path in candidates where !path.isEmpty {
            if TerminalAdapterHelpers.isExecutablePresent(path) {
                return path
            }
        }
        return kind.defaultBinaryPath ?? "/Applications/kitty.app/Contents/MacOS/kitty"
    }

    var isInstalled: Bool {
        if TerminalAdapterHelpers.isAppInstalled(bundleID: kind.bundleID) { return true }
        return TerminalAdapterHelpers.isExecutablePresent(binaryPath)
    }

    func focusSession(tty: String) -> Bool {
        let fullTTY = TerminalAdapterHelpers.fullTTY(tty)

        // 1) Ask kitty for its window list.
        let listResult: TerminalAdapterHelpers.ProcessOutput
        do {
            listResult = try TerminalAdapterHelpers.runProcess(
                binaryPath,
                arguments: ["@", "--to", Self.socketPath, "ls"],
                kind: kind
            )
        } catch {
            print("[KittyAdapter] focus ls failed: \(error)")
            return false
        }
        guard listResult.didSucceed,
              let data = listResult.stdout.data(using: .utf8) else {
            return false
        }

        // 2) Walk the JSON tree looking for a window whose foreground process
        //    or tab tty matches our target. kitty's schema:
        //      [ { tabs: [ { windows: [ { id, foreground_processes: [{ cwd, cmdline }], ... } ] } ] } ]
        guard let tabs = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else {
            return false
        }

        guard let windowID = Self.findWindowID(in: tabs, matchingTTY: fullTTY) else {
            return false
        }

        // 3) Focus + bring kitty to front. We also `osascript activate` since
        //    `kitty @ focus-window` only changes intra-app focus.
        let focusOK = (try? TerminalAdapterHelpers.runProcess(
            binaryPath,
            arguments: ["@", "--to", Self.socketPath, "focus-window", "--match", "id:\(windowID)"],
            kind: kind
        ))?.didSucceed ?? false
        if !focusOK { return false }

        let activateScript = """
        tell application "kitty" to activate
        """
        _ = TerminalAdapterHelpers.appleScriptResult(activateScript)
        return true
    }

    /// Write text to a kitty window matching `tty` via `kitty @ send-text`.
    /// Does NOT bring kitty to front. Falls back to POSIX tty write on failure.
    func writeText(tty: String, text: String) -> Bool {
        let fullTTY = TerminalAdapterHelpers.fullTTY(tty)

        // First find the matching window id via `kitty @ ls`
        guard let windowID = findWindowIDForTTY(fullTTY) else {
            // kitty remote control unavailable — fall back to POSIX
            guard let data = (text + "\n").data(using: .utf8),
                  let handle = FileHandle(forWritingAtPath: fullTTY) else { return false }
            defer { handle.closeFile() }
            handle.write(data)
            return true
        }

        // Send text via kitty remote control (includes trailing newline)
        let textWithNewline = text + "\n"
        let result = try? TerminalAdapterHelpers.runProcess(
            binaryPath,
            arguments: ["@", "--to", Self.socketPath, "send-text", "--match", "id:\(windowID)", textWithNewline],
            kind: kind
        )
        if result?.didSucceed == true { return true }

        // Fallback to POSIX
        guard let data = (text + "\n").data(using: .utf8),
              let handle = FileHandle(forWritingAtPath: fullTTY) else { return false }
        defer { handle.closeFile() }
        handle.write(data)
        return true
    }

    /// Look up a kitty window id matching `fullTTY` from `kitty @ ls`.
    private func findWindowIDForTTY(_ fullTTY: String) -> Int? {
        let listResult: TerminalAdapterHelpers.ProcessOutput
        do {
            listResult = try TerminalAdapterHelpers.runProcess(
                binaryPath,
                arguments: ["@", "--to", Self.socketPath, "ls"],
                kind: kind
            )
        } catch { return nil }

        guard listResult.didSucceed,
              let data = listResult.stdout.data(using: .utf8),
              let tabs = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else {
            return nil
        }
        return Self.findWindowID(in: tabs, matchingTTY: fullTTY)
    }

    func launch(command: String, cwd: String) throws {
        // `--single-instance` makes repeat launches reuse the same kitty
        // process; `--listen-on` exposes the remote-control socket so future
        // `focusSession` calls can reach it.
        let arguments = [
            "--single-instance",
            "--listen-on", Self.socketPath,
            "--directory", cwd,
            "--hold",
            "bash", "-c", command
        ]

        let result = try TerminalAdapterHelpers.runProcess(
            binaryPath,
            arguments: arguments,
            kind: kind
        )

        if !result.didSucceed {
            throw TerminalAdapterError.processFailed(
                kind,
                "kitty exit \(result.exitStatus): \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
            )
        }
    }

    // MARK: - JSON walking

    /// Best-effort: locate a kitty window whose foreground process cwd or
    /// tty hint matches `fullTTY`. We can't ask kitty for the tty directly,
    /// so we look at the foreground process cmdline for a matching tty
    /// substring, then fall back to any pty-attached window.
    private static func findWindowID(in tabs: [Any], matchingTTY fullTTY: String) -> Int? {
        for entry in tabs {
            guard let dict = entry as? [String: Any] else { continue }
            if let id = matchingWindow(in: dict, fullTTY: fullTTY) {
                return id
            }
        }
        return nil
    }

    private static func matchingWindow(in os: [String: Any], fullTTY: String) -> Int? {
        if let osTabs = os["tabs"] as? [[String: Any]] {
            for tab in osTabs {
                guard let windows = tab["windows"] as? [[String: Any]] else { continue }
                for win in windows {
                    if let id = win["id"] as? Int,
                       windowMatches(win, fullTTY: fullTTY) {
                        return id
                    }
                }
            }
        }
        return nil
    }

    private static func windowMatches(_ window: [String: Any], fullTTY: String) -> Bool {
        // Try every cmdline of every foreground process; if anyone references
        // our tty (rare but possible) we treat it as a match.
        if let procs = window["foreground_processes"] as? [[String: Any]] {
            for proc in procs {
                if let cmdline = proc["cmdline"] as? [String],
                   cmdline.contains(where: { $0.contains(fullTTY) }) {
                    return true
                }
            }
        }
        return false
    }
}
