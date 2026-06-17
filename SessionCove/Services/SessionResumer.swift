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
        DiagnosticLogger.shared.log("resume: \(session.id) at \(session.projectPath)", module: "SessionResumer")

        // Delegate to `focusOrLaunch`, which is a strict superset of the old
        // resume logic: same TTY lookup + ancestor-adapter focus, but with two
        // extra fallbacks before giving up and launching a new window —
        // `activateTerminalForPid` (activate the owning app even when we can't
        // target the exact tty) and a ProcessDetector cwd check. Those
        // fallbacks are what make IDE-integrated-terminal sessions (VS Code /
        // Cursor) refocus instead of spawning a duplicate window. The session
        // list's "open" used to call the leaner path and skipped them, which
        // is why it still opened a new terminal after the completion-toast
        // path was fixed. Routing both through one function keeps them in sync.
        focusOrLaunch(
            sessionId: session.id,
            projectPath: session.projectPath,
            providerId: session.providerId
        )
    }

    /// Used by the completion-toast "打开 session" button when the
    /// SessionScanner hasn't yet ingested the just-finished JSONL — we don't
    /// have a `SessionRecord` to pass into `resume(session:)`, but we do
    /// have the session id (from the Stop payload) and the project cwd.
    /// Same focus → launch fallback chain as `resume`, just without
    /// requiring a fully-built SessionRecord.
    static func focusOrLaunch(
        sessionId: String,
        projectPath: String,
        providerId: String = "claude"
    ) {
        print("[SessionResumer] focusOrLaunch sessionId=\(sessionId.prefix(12)) project=\(projectPath) provider=\(providerId)")
        DiagnosticLogger.shared.log("focusOrLaunch: \(sessionId.prefix(12)) at \(projectPath)", module: "SessionResumer")
        DispatchQueue.global(qos: .userInitiated).async {
            let lookup = findSessionTTY(sessionId: sessionId, projectPath: projectPath)
            if let lookup, focusExistingSession(tty: lookup.tty, pid: lookup.pid) {
                print("[SessionResumer] focusOrLaunch focused tty=\(lookup.tty)")
                focusIDEWorkspaceIfNeeded(pid: lookup.pid, projectPath: projectPath)
                return
            }

            // We found a live process but couldn't focus its specific TTY.
            // The session IS running — just activate the terminal app itself
            // rather than launching a broken `claude --resume` in a new window.
            if let lookup {
                if activateTerminalForPid(lookup.pid) {
                    print("[SessionResumer] focusOrLaunch activated terminal app for pid=\(lookup.pid)")
                    return
                }
            }

            // findSessionTTY missed entirely — use ProcessDetector as a
            // backup to verify whether a live agent exists at projectPath
            // before giving up and launching a new session.
            if lookup == nil {
                let activeLocations = ProcessDetector.shared.detectActiveAgentLocations()
                let targetCwd = normalizePath(projectPath)
                if activeLocations.contains(where: { normalizePath($0.cwd) == targetCwd }) {
                    if activateAnyTerminal() {
                        print("[SessionResumer] focusOrLaunch activated terminal via ProcessDetector fallback")
                        return
                    }
                }
            }

            // No live process found at projectPath, or every activation
            // attempt failed. Launch a new session as a last resort.
            launchNewSession(
                sessionId: sessionId,
                projectPath: projectPath,
                providerId: providerId
            )
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

    private static func findSessionTTY(sessionId: String, projectPath: String) -> (tty: String, pid: Int32)? {
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

        // Phase 2 candidates: bare agent processes (no sessionId in args).
        // Resolve them by cwd against projectPath. The set of qualifying
        // binaries comes from `AgentProviderRegistry.enabled()` so a future
        // Qoder/Codex provider drops in without code edits — today the set
        // is just `["claude"]` so behavior is byte-identical.
        let agentBinaries = Set(enabledAgentBinaries())
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
            if !sessionId.isEmpty, argsJoined.contains(sessionId) {
                return (tty, pid)
            }

            if agentBinaries.contains(commName) {
                claudePidTty.append((pid, tty))
            }
        }

        // Phase 2: bare claude process whose cwd matches projectPath.
        let targetCwd = normalizePath(projectPath)
        var matches: [(pid: Int32, tty: String)] = []
        for entry in claudePidTty {
            if let cwd = lsofCwd(pid: entry.pid), normalizePath(cwd) == targetCwd {
                matches.append((pid: entry.pid, tty: entry.tty))
            }
        }

        // Phase 2.5: when multiple claude processes share the same cwd
        // (user opened several sessions in the same project), narrow them
        // by checking which pid has the target session's transcript JSONL
        // open. Claude Code keeps `~/.claude/projects/<encoded>/<sid>.jsonl`
        // on a long-lived fd while the session is alive, so `lsof -p`
        // listing per-pid open files is a reliable signal. Without this
        // the fallback below picks min-pid which is wrong ~67% of the
        // time when 3 sessions are running.
        if !sessionId.isEmpty, matches.count > 1 {
            for entry in matches {
                if processHasOpenFile(pid: entry.pid, fileSubstring: sessionId) {
                    print("[SessionResumer] Matched by transcript fd pid=\(entry.pid) tty=\(entry.tty) sid=\(sessionId.prefix(12))")
                    return (tty: entry.tty, pid: entry.pid)
                }
            }
            print("[SessionResumer] Multi-match (\(matches.count)) but no transcript fd hit for sid=\(sessionId.prefix(12)); falling back to min-pid")
        }

        // Fallback: lowest-pid (oldest) match. Single-match case lands
        // here directly, which is the common scenario.
        if let first = matches.min(by: { $0.pid < $1.pid }) {
            print("[SessionResumer] Matched bare claude pid=\(first.pid) tty=\(first.tty) by cwd=\(targetCwd)")
            return (tty: first.tty, pid: first.pid)
        }
        return nil
    }

    /// True if `pid`'s open files (per `lsof -p`) contain `fileSubstring`
    /// anywhere in the path. Used to disambiguate same-cwd claude
    /// processes by checking which one has the target session's
    /// transcript JSONL open. Returns false on any lsof error — the
    /// caller falls back to a min-pid heuristic in that case.
    private static func processHasOpenFile(pid: Int32, fileSubstring: String) -> Bool {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        // -Fn emits filenames only, one per line prefixed with `n`. Cheaper
        // to parse + dramatically less output than the default full table.
        process.arguments = ["-p", String(pid), "-Fn"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do { try process.run() } catch { return false }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return false }
        return output.contains(fileSubstring)
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

    /// After successfully focusing an IDE-hosted session, try to open the
    /// project workspace in the IDE so the user lands in the correct window.
    private static func focusIDEWorkspaceIfNeeded(pid: Int32, projectPath: String) {
        guard let kind = TerminalDetector.ancestorTerminal(of: pid) else { return }
        switch kind {
        case .vscode, .cursor:
            if IDEWindowAdapter.focusWorkspace(path: projectPath, kind: kind) {
                print("[SessionResumer] IDE workspace opened: \(projectPath)")
            }
        default:
            break
        }
    }

    // MARK: - Launch

    private static func launchNewSession(
        sessionId: String,
        projectPath: String,
        providerId: String = "claude"
    ) {
        // Resolve the provider via the registry so the launch command is
        // sourced from `AgentProvider.{resume,bareLaunch}Command`. Unknown
        // providerId falls back to claude — there is always a claude
        // provider registered (`bootstrap()` in AgentProviderRegistry).
        let provider = readProvider(providerId: providerId)
            ?? readProvider(providerId: "claude")!
        let adapter = TerminalDetector.resolvedTerminal()
        let command = sessionId.isEmpty
            ? provider.bareLaunchCommand()
            : provider.resumeCommand(sessionId: sessionId)
        print("[SessionResumer] Launching new session for \(sessionId.prefix(12)) via \(adapter.kind.displayName) provider=\(provider.id)")
        do {
            try adapter.launch(command: command, cwd: projectPath)
        } catch {
            print("[SessionResumer] launch via \(adapter.kind.displayName) failed: \(error)")
            fallbackTerminalApp(command: command, cwd: projectPath)
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

    // MARK: - Provider registry

    /// Look up a provider by id, hopping to main if necessary because
    /// `AgentProviderRegistry` is `@MainActor`. Most callers run on the
    /// background `userInitiated` queue (resume/focusOrLaunch/launchNew),
    /// so the sync hop is the common path.
    private static func readProvider(providerId: String) -> (any AgentProvider)? {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                AgentProviderRegistry.shared.provider(for: providerId)
            }
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                AgentProviderRegistry.shared.provider(for: providerId)
            }
        }
    }

    /// Union of every enabled provider's `processBinaryNames`, deduped in
    /// registry order. Mirrors the helper in `TerminalDetector`/`ProcessDetector`
    /// so all three services agree on which `comm` values count as "an agent
    /// is alive". Today the set is just `["claude"]`.
    private static func enabledAgentBinaries() -> [String] {
        let providers: [any AgentProvider]
        if Thread.isMainThread {
            providers = MainActor.assumeIsolated {
                AgentProviderRegistry.shared.enabled()
            }
        } else {
            providers = DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    AgentProviderRegistry.shared.enabled()
                }
            }
        }
        var binaries: [String] = []
        var seen: Set<String> = []
        for provider in providers {
            for binary in provider.processBinaryNames where !seen.contains(binary) {
                binaries.append(binary)
                seen.insert(binary)
            }
        }
        return binaries
    }

    // MARK: - Terminal activation (focusOrLaunch helpers)

    /// Activate the terminal that owns `pid` by walking its ancestor tree.
    /// Falls back to activating any running terminal in priority order.
    private static func activateTerminalForPid(_ pid: Int32) -> Bool {
        if let kind = TerminalDetector.ancestorTerminal(of: pid) {
            if TerminalAdapterHelpers.activateRunningApp(bundleID: kind.bundleID) {
                return true
            }
        }
        return activateAnyTerminal()
    }

    /// Activate any known running terminal app, in priority order.
    private static func activateAnyTerminal() -> Bool {
        for kind in TerminalDetector.supportedKinds {
            if TerminalAdapterHelpers.activateRunningApp(bundleID: kind.bundleID) {
                return true
            }
        }
        return false
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
        // IDE integrated terminals (VS Code / Cursor): focus = activate the
        // IDE window. Without this, a session running in an IDE terminal
        // falls through every real-terminal adapter and `launchNewSession`
        // spawns a duplicate window. The IDE adapter brings the user back to
        // the existing window instead.
        case .vscode, .cursor: return IDEWindowAdapter(kind: kind)
        }
    }
}
