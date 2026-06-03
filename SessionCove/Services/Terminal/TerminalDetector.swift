import AppKit
import Foundation

/// Centralized "which terminal should Cove resume into?" decision logic.
///
/// Three layers, all static so callers don't have to thread an instance:
/// - `installedTerminals()` — enumerate supported terminals registered with
///   Launch Services, in priority order.
/// - `ancestorTerminal(of:)` — given a pid (typically a running `claude`),
///   walk parent process IDs to find which terminal app spawned it.
/// - `resolvedTerminal()` — priority cascade that picks the active adapter:
///     1. Explicit user preference (`CoveSettings.preferredTerminal`)
///     2. Ancestor of any running `claude` process (best-effort)
///     3. First entry from `installedTerminals()`
///     4. `Terminal.app` (always-present fallback bundled with macOS)
///
/// Warp is intentionally excluded from v1 — see `WarpAdapter` for the
/// "YAML side-effect, no focus path" rationale. Even when installed it is
/// skipped by `adapter(for:)` so the cascade falls through to Terminal.app.
enum TerminalDetector {

    /// Priority order shared by `installedTerminals()` and the fallback
    /// branch of `resolvedTerminal()`. iTerm2 first because it is the
    /// historical golden path; Terminal.app second because it is always
    /// installed; the rest follow by quality of focus support.
    static let supportedKinds: [TerminalKind] = [
        .iterm,
        .terminalApp,
        .ghostty,
        .kitty,
        .wezterm,
        .alacritty
    ]

    /// True when the currently frontmost macOS app is a known terminal.
    /// Used by the completion-toast suppression flow: if the user is
    /// already on a terminal they can see the result in-session — no
    /// popup needed. Warp is included here (even though it's not in
    /// `supportedKinds` for resume) because for the "is the user looking
    /// at a terminal" question Warp absolutely counts.
    static func isFrontmostAppATerminal() -> Bool {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }
        return TerminalKind.allCases.contains { $0.bundleID == bundleID }
    }

    // MARK: - Public detection

    /// Terminals supported by Cove that are currently registered with
    /// Launch Services. The result is filtered through `supportedKinds`,
    /// so Warp never appears even if installed. Thread-safe — NSWorkspace
    /// `urlForApplication(withBundleIdentifier:)` is documented as callable
    /// from any thread.
    static func installedTerminals() -> [TerminalKind] {
        supportedKinds.filter { kind in
            TerminalAdapterHelpers.isAppInstalled(bundleID: kind.bundleID)
        }
    }

    /// Walk parent process IDs from `pid` up to PID 1; return the first
    /// ancestor whose executable name matches a known terminal. Returns
    /// `nil` when the chain terminates before hitting a terminal (e.g.
    /// `claude` was spawned by a non-terminal task runner) or when the
    /// safety bound is exceeded.
    static func ancestorTerminal(of pid: Int32) -> TerminalKind? {
        var current = pid
        var hops = 0
        // Bound the walk so a corrupted /proc-equivalent or parent loop
        // can't hang the call. macOS process trees are rarely > ~10 deep.
        while current > 1 && hops < 64 {
            if let command = processCommand(pid: current),
               let kind = matchTerminal(commandLine: command) {
                return kind
            }
            guard let parent = parentPid(of: current),
                  parent > 0,
                  parent != current else {
                return nil
            }
            current = parent
            hops += 1
        }
        return nil
    }

    /// Adapter that should service "resume session" calls right now.
    /// See type-level docs for the priority cascade. Callable from any
    /// thread — we hop briefly to main only to read the user's preferred
    /// terminal from `CoveSettings` (a `@MainActor` class).
    static func resolvedTerminal() -> TerminalAdapter {
        // 1. Explicit user choice wins, but only if the chosen terminal is
        //    still installed. Otherwise we fall through (rather than
        //    surprising the user with a hard failure).
        let preferred = readPreferredTerminal()
        if let preferred,
           let adapter = adapter(for: preferred),
           adapter.isInstalled {
            return adapter
        }

        // 2. Process ancestry — if any enabled agent is currently running
        //    inside a terminal, prefer that one so resumes feel local to
        //    the user's current session.
        if let kind = ancestorOfActiveAgent(),
           let adapter = adapter(for: kind),
           adapter.isInstalled {
            return adapter
        }

        // 3. Whatever the user has installed, in our priority order.
        if let kind = installedTerminals().first,
           let adapter = adapter(for: kind) {
            return adapter
        }

        // 4. Terminal.app is bundled with macOS — guaranteed fallback.
        return TerminalAppAdapter()
    }

    // MARK: - Private — adapter wiring

    /// Map a `TerminalKind` to its concrete adapter struct. Returns `nil`
    /// for kinds that intentionally have no v1 adapter (currently just
    /// Warp), letting `resolvedTerminal` skip past them.
    private static func adapter(for kind: TerminalKind) -> TerminalAdapter? {
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

    /// Read the user's preferred terminal from `CoveSettings`, hopping to
    /// main since the settings type is `@MainActor`-isolated. Synchronous;
    /// callable from any background queue — `DispatchQueue.main.sync` is
    /// safe here because callers (SessionResumer) never run on main.
    /// If we ARE on main (rare path), read directly to avoid sync deadlock.
    private static func readPreferredTerminal() -> TerminalKind? {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { CoveSettings.shared.preferredTerminal }
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated { CoveSettings.shared.preferredTerminal }
        }
    }

    // MARK: - Private — process tree walking

    /// Find the first running agent (any enabled provider's binary) whose
    /// ancestry resolves to a known terminal. We scan every matching pid
    /// because a user might have multiple Cove-managed sessions in flight;
    /// the first match wins.
    ///
    /// `binaries == nil` (the default) walks the union of enabled providers'
    /// `processBinaryNames`. Pass an explicit list to scope the lookup to a
    /// specific provider (e.g. when the caller already knows which agent it
    /// cares about and wants to skip the registry hop).
    private static func ancestorOfActiveAgent(binaries: [String]? = nil) -> TerminalKind? {
        let resolved = binaries ?? defaultAgentBinaries()
        guard !resolved.isEmpty else { return nil }
        for pid in listAgentPids(binaries: resolved) {
            if let kind = ancestorTerminal(of: pid) {
                return kind
            }
        }
        return nil
    }

    /// Backward-compat wrapper. Swift can't `typealias` a function, so this
    /// keeps the original symbol callable for any future code path that
    /// reaches for the Claude-only spelling. Defaults match the historical
    /// behavior because Claude is the only enabled provider today.
    private static func ancestorOfRunningClaude() -> TerminalKind? {
        ancestorOfActiveAgent()
    }

    /// Union of enabled providers' `processBinaryNames`, in registry order.
    /// Hops to main if needed since `AgentProviderRegistry` is `@MainActor`.
    private static func defaultAgentBinaries() -> [String] {
        let providers: [any AgentProvider]
        if Thread.isMainThread {
            providers = MainActor.assumeIsolated { AgentProviderRegistry.shared.enabled() }
        } else {
            providers = DispatchQueue.main.sync {
                MainActor.assumeIsolated { AgentProviderRegistry.shared.enabled() }
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

    /// Match the basename of `ps -o command=` output against known
    /// terminal executables. Lowercased to tolerate casing differences
    /// across releases (`iTerm2` vs `iterm2`, etc.).
    private static func matchTerminal(commandLine: String) -> TerminalKind? {
        let trimmed = commandLine.trimmingCharacters(in: .whitespacesAndNewlines)
        // `command=` returns "executable args ...". Take the path before
        // the first space; this misclassifies paths containing spaces, but
        // /Applications and /opt/homebrew install locations don't.
        let executable = trimmed
            .split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? trimmed
        let basename = ((executable as NSString).lastPathComponent).lowercased()

        switch basename {
        case "iterm2", "iterm":
            return .iterm
        case "terminal":
            return .terminalApp
        case "ghostty":
            return .ghostty
        case "kitty":
            return .kitty
        // WezTerm's GUI process is named `wezterm-gui`; tmux-style binaries
        // sometimes report just `wezterm`.
        case "wezterm-gui", "wezterm":
            return .wezterm
        case "alacritty":
            return .alacritty
        // Warp's bundle id is `dev.warp.Warp-Stable` and the executable
        // inside its .app is named `stable`.
        case "stable", "warp":
            return .warp
        default:
            return nil
        }
    }

    private static func parentPid(of pid: Int32) -> Int32? {
        guard let raw = runPS(arguments: ["-o", "ppid=", "-p", String(pid)]) else {
            return nil
        }
        return Int32(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func processCommand(pid: Int32) -> String? {
        guard let raw = runPS(arguments: ["-o", "command=", "-p", String(pid)]) else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// All running pids whose `comm` basename is in `binaries`. Mirrors the
    /// matching rule in `ProcessDetector` so detection is consistent.
    private static func listAgentPids(binaries: [String]) -> [Int32] {
        guard !binaries.isEmpty,
              let raw = runPS(arguments: ["-axo", "pid=,comm="]) else { return [] }
        let binarySet = Set(binaries)
        var pids: [Int32] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 2, let pid = Int32(parts[0]) else { continue }
            let comm = parts[1..<parts.count].joined(separator: " ")
            let basename = (comm as NSString).lastPathComponent
            if binarySet.contains(basename) {
                pids.append(pid)
            }
        }
        return pids
    }

    /// Backward-compat wrapper around `listAgentPids` scoped to the current
    /// enabled providers' binaries. Today that's just `claude`.
    private static func listClaudePids() -> [Int32] {
        listAgentPids(binaries: defaultAgentBinaries())
    }

    /// Run `/bin/ps` with the given arguments; return stdout on success,
    /// `nil` on any failure (process spawn, non-zero exit, decode error).
    /// Stderr is dropped — `ps` is noisy when querying dead pids and we
    /// always treat that as "no info, walk stops".
    private static func runPS(arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
