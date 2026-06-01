import AppKit

/// Top-level facade for "the user clicked a session — bring it back".
///
/// Wire-phase responsibilities:
/// 1. Locate the live TTY + pid for the session via `ps`/`lsof`
/// 2. Try the ancestor terminal first (the one that actually owns `claude`)
/// 3. Fall back to iTerm2 / Terminal.app focus attempts
/// 4. As a last resort, launch a fresh window via the resolved adapter
///
/// All terminal-specific scripting now lives in
/// `Services/Terminal/Adapters/*Adapter.swift`. This file no longer talks
/// AppleScript directly — it composes adapter calls.
struct SessionResumer {
    static func resume(session: SessionRecord) {
        print("[SessionResumer] resume called for session: \(session.id) project: \(session.projectPath)")

        // Everything below — TTY lookup, ancestor walk (up to 128 ps calls),
        // adapter focus/launch (osascript or kitty/wezterm CLI) — must stay
        // off the main thread. Running these on main under @MainActor caused
        // the "spinner forever" hang: ~50 ps invocations + an osascript that
        // can block on a hidden TCC dialog never let the RunLoop spin.
        DispatchQueue.global(qos: .userInitiated).async {
            let lookup = findSessionTTY(session: session)
            if let lookup {
                print("[SessionResumer] TTY lookup result: tty=\(lookup.tty) pid=\(lookup.pid)")
            } else {
                print("[SessionResumer] TTY lookup result: nil")
            }

            if let lookup, focusExistingSession(tty: lookup.tty, pid: lookup.pid) {
                return
            }
            // No TTY found, or TTY not present in any known terminal —
            // open a fresh window with `claude --resume <id>` instead of
            // leaving the user staring at an unrelated front-most app.
            launchNewSession(session: session)
        }
    }

    static func launchNew(projectPath: String) {
        print("[SessionResumer] Launching new Claude session in: \(projectPath)")
        DispatchQueue.global(qos: .userInitiated).async {
            let adapter = TerminalDetector.resolvedTerminal()
            do {
                try adapter.launch(command: "claude", cwd: projectPath)
                print("[SessionResumer] launched new session via \(adapter.kind.displayName)")
            } catch {
                print("[SessionResumer] launchNew failed via \(adapter.kind.displayName): \(error)")
                // Last-ditch fallback: Terminal.app is bundled with macOS so it
                // is always present and reliable.
                fallbackTerminalApp(command: "claude", cwd: projectPath)
            }
        }
    }

    // MARK: - TTY lookup

    private static func findSessionTTY(session: SessionRecord) -> (tty: String, pid: Int32)? {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,tty=,comm=,args="]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            print("[SessionResumer] Starting TTY lookup")
            try process.run()
        } catch {
            print("[SessionResumer] ps failed: \(error)")
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        print("[SessionResumer] ps exited with status: \(process.terminationStatus)")

        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8) else { return nil }

        // Phase 2 candidates: bare `claude` processes (no sessionId in args).
        // Resolve them by cwd against session.projectPath.
        var claudePidTty: [(pid: Int32, tty: String)] = []

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 4, let pid = Int32(parts[0]) else { continue }

            let tty = parts[1]
            guard tty != "??" else { continue }

            let commName = (parts[2] as NSString).lastPathComponent
            let argsJoined = parts[3..<parts.count].joined(separator: " ")

            // Phase 1: args literally contain the session id (covers `claude --resume <id>`).
            if argsJoined.contains(session.id) {
                return (tty, pid)
            }

            if commName == "claude" {
                claudePidTty.append((pid, tty))
            }
        }

        // Phase 2: bare claude process whose cwd matches session.projectPath.
        let targetCwd = normalizePath(session.projectPath)
        for (pid, tty) in claudePidTty {
            if let cwd = lsofCwd(pid: pid), normalizePath(cwd) == targetCwd {
                print("[SessionResumer] Matched bare claude pid=\(pid) tty=\(tty) by cwd=\(cwd)")
                return (tty, pid)
            }
        }
        return nil
    }

    private static func lsofCwd(pid: Int32) -> String? {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-a", "-p", String(pid), "-d", "cwd", "-F", "n"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do { try process.run() } catch { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return nil }
        for line in output.components(separatedBy: "\n") where line.hasPrefix("n") {
            return String(line.dropFirst())
        }
        return nil
    }

    private static func normalizePath(_ path: String) -> String {
        var p = path
        while p.count > 1 && p.hasSuffix("/") {
            p = String(p.dropLast())
        }
        return p
    }

    // MARK: - Focus cascade

    /// Three-tier focus attempt:
    /// 1. Ancestor terminal of the live `claude` pid — most accurate.
    /// 2. iTerm2 — historical golden path for users without ancestor info.
    /// 3. Terminal.app — guaranteed present; last focus attempt before
    ///    falling back to launching a fresh window.
    private static func focusExistingSession(tty: String, pid: Int32) -> Bool {
        // 1. Ancestor walk — if we can prove which terminal owns this pid,
        //    target it directly. Avoids cross-terminal mis-focus when the user
        //    has both iTerm and Terminal.app open.
        if let kind = TerminalDetector.ancestorTerminal(of: pid),
           let adapter = adapterFor(kind),
           adapter.isInstalled {
            print("[SessionResumer] focus via ancestor adapter: \(kind.displayName)")
            if adapter.focusSession(tty: tty) {
                return true
            }
        }

        // 2. iTerm2 fallback — direct adapter, no detector prefs.
        let iterm = ITermAdapter()
        if iterm.isInstalled {
            print("[SessionResumer] focus via iTerm fallback")
            if iterm.focusSession(tty: tty) {
                return true
            }
        }

        // 3. Terminal.app fallback — always installed.
        print("[SessionResumer] focus via Terminal.app fallback")
        if TerminalAppAdapter().focusSession(tty: tty) {
            return true
        }

        return false
    }

    // MARK: - Launch

    private static func launchNewSession(session: SessionRecord) {
        let adapter = TerminalDetector.resolvedTerminal()
        let command = "claude --resume \(session.id)"
        print("[SessionResumer] Launching new session for \(session.id) via \(adapter.kind.displayName)")
        do {
            try adapter.launch(command: command, cwd: session.projectPath)
        } catch {
            print("[SessionResumer] launch via \(adapter.kind.displayName) failed: \(error)")
            fallbackTerminalApp(command: command, cwd: session.projectPath)
        }
    }

    /// Last-ditch fallback when the resolved adapter throws. Terminal.app is
    /// bundled with macOS so this should always succeed; if it doesn't, log
    /// loudly and let the user know via console.
    private static func fallbackTerminalApp(command: String, cwd: String) {
        let adapter = TerminalAppAdapter()
        do {
            try adapter.launch(command: command, cwd: cwd)
            print("[SessionResumer] fallback Terminal.app succeeded")
        } catch {
            print("[SessionResumer] fallback Terminal.app also failed: \(error)")
        }
    }

    // MARK: - Adapter lookup

    /// Map a `TerminalKind` to its concrete adapter. Mirrors
    /// `TerminalDetector.adapter(for:)` (which is private to that file). We
    /// duplicate the switch here so SessionResumer can route the ancestor
    /// kind directly without exposing detector internals.
    private static func adapterFor(_ kind: TerminalKind) -> TerminalAdapter? {
        switch kind {
        case .iterm:        return ITermAdapter()
        case .terminalApp:  return TerminalAppAdapter()
        case .ghostty:      return GhosttyAdapter()
        case .kitty:        return KittyAdapter()
        case .wezterm:      return WezTermAdapter()
        case .alacritty:    return AlacrittyAdapter()
        case .warp:         return nil  // intentional — see WarpAdapter
        }
    }
}
