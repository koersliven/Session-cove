import Foundation

/// Manages one or more `ManagedPTY` instances representing Claude sessions
/// spawned directly by Session Cove (as opposed to "observer" sessions where
/// the user runs claude in iTerm independently).
///
/// Managed sessions hold the pty master fd, enabling reliable stdin injection
/// for AskUserQuestion flows -- the primary motivation for this subsystem.
///
/// Thread safety: all public API is `@MainActor` (session bookkeeping, state
/// updates). The per-session read loop runs on a background `DispatchQueue`
/// and dispatches output back to main via the `outputCallback`.
@MainActor
final class ManagedSessionController {

    // MARK: - Singleton

    static let shared = ManagedSessionController()

    // MARK: - Types

    /// Metadata tracked alongside the live pty.
    struct SessionEntry: Sendable {
        let pty: ManagedPTY
        let cwd: String
        let startedAt: Date
    }

    // MARK: - State

    /// Active managed sessions keyed by sessionId.
    private(set) var sessions: [String: SessionEntry] = [:]

    /// Called on a background queue whenever a managed session produces output.
    /// Parameters: (sessionId, outputChunk as UTF-8 string).
    /// Consumers (e.g. a future embedded terminal view) assign this closure.
    nonisolated(unsafe) var outputCallback: ((String, String) -> Void)?

    /// Background queue for read loops.
    private let readQueue = DispatchQueue(
        label: "com.session-cove.managed-pty-read",
        qos: .userInitiated,
        attributes: .concurrent
    )

    // MARK: - Init

    private init() {}

    // MARK: - Session Lifecycle

    /// Spawn a new managed Claude session.
    ///
    /// - Parameters:
    ///   - cwd: Working directory for the claude process.
    ///   - sessionId: Explicit session id. If `nil`, a new UUID is generated.
    ///   - resume: If `true`, resumes an existing session (`--resume <id>`).
    ///             If `false`, starts a new session (`--session-id <id>`).
    ///   - mode: Permission mode string (e.g. "default", "plan", "bypassPermissions").
    ///   - model: Optional model override (e.g. "claude-sonnet-4-20250514").
    /// - Returns: The sessionId on success, `nil` if spawn failed.
    @discardableResult
    func startSession(
        cwd: String,
        sessionId: String? = nil,
        resume: Bool = false,
        mode: String = "default",
        model: String? = nil
    ) -> String? {
        let sid = sessionId ?? UUID().uuidString

        // Don't double-spawn
        if sessions[sid] != nil {
            print("[ManagedSessionController] session \(sid.prefix(12)) already active")
            return sid
        }

        // Resolve claude binary path
        guard let claudeBin = resolveClaudeBinary() else {
            print("[ManagedSessionController] claude binary not found in PATH")
            return nil
        }

        // Build argv
        var args: [String] = [claudeBin]
        if resume {
            args += ["--resume", sid]
        } else {
            args += ["--session-id", sid]
        }
        args += ["--permission-mode", mode]
        if let model {
            args += ["--model", model]
        }

        // Spawn
        guard let pty = ManagedPTY.spawn(
            command: claudeBin,
            args: args,
            cwd: cwd,
            env: ["TERM": "xterm-256color", "COLORTERM": "truecolor"],
            sessionId: sid
        ) else {
            print("[ManagedSessionController] forkpty spawn failed for session \(sid.prefix(12))")
            return nil
        }

        let entry = SessionEntry(pty: pty, cwd: cwd, startedAt: Date())
        sessions[sid] = entry

        // Start background read loop
        startReadLoop(sessionId: sid, pty: pty)

        print("[ManagedSessionController] started managed session \(sid.prefix(12)) in \(cwd)")
        return sid
    }

    /// Write text to a managed session's stdin (appears as if the user typed it).
    /// Appends `\r` (carriage return) to simulate pressing Enter unless the
    /// text already ends with a newline/CR.
    ///
    /// - Returns: `true` if the write succeeded, `false` if session not found or write failed.
    @discardableResult
    func writeToSession(sessionId: String, text: String) -> Bool {
        guard let entry = sessions[sessionId], entry.pty.isAlive else {
            print("[ManagedSessionController] writeToSession: session \(sessionId.prefix(12)) not found or dead")
            return false
        }

        // Append CR if needed (terminal convention: Enter = \r)
        let payload: String
        if text.hasSuffix("\n") || text.hasSuffix("\r") {
            payload = text
        } else {
            payload = text + "\r"
        }

        return entry.pty.write(payload)
    }

    /// Kill a managed session and remove it from the active set.
    func killSession(sessionId: String) {
        guard let entry = sessions.removeValue(forKey: sessionId) else { return }
        entry.pty.kill()
        print("[ManagedSessionController] killed managed session \(sessionId.prefix(12))")
    }

    /// Resize the pty window for a managed session.
    func resizeSession(sessionId: String, cols: Int, rows: Int) {
        guard let entry = sessions[sessionId] else { return }
        entry.pty.resize(cols: cols, rows: rows)
    }

    /// Check if a given sessionId is managed by us (vs. an external iTerm session).
    func isManaged(sessionId: String) -> Bool {
        return sessions[sessionId] != nil
    }

    // MARK: - Private

    /// Background read loop that polls the pty master fd and dispatches
    /// output chunks to `outputCallback`.
    private func startReadLoop(sessionId: String, pty: ManagedPTY) {
        readQueue.async { [weak self] in
            while pty.isAlive {
                guard let data = pty.read() else {
                    // nil = EOF or error, child exited
                    break
                }
                if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                    self?.outputCallback?(sessionId, text)
                }
                // Brief sleep to avoid busy-spinning when no data available
                usleep(10_000) // 10ms
            }

            // Session exited -- remove from active set on main
            DispatchQueue.main.async {
                guard let self else { return }
                if self.sessions[sessionId] != nil {
                    self.sessions.removeValue(forKey: sessionId)
                    print("[ManagedSessionController] session \(sessionId.prefix(12)) exited, removed from active set")
                }
            }
        }
    }

    /// Resolve the `claude` binary from common locations.
    private func resolveClaudeBinary() -> String? {
        // Check common install paths
        let candidates = [
            "/usr/local/bin/claude",
            "\(NSHomeDirectory())/.local/bin/claude",
            "\(NSHomeDirectory())/.npm-global/bin/claude",
            "/opt/homebrew/bin/claude",
        ]

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Fall back to `which claude`
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["claude"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if process.terminationStatus == 0,
               let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                return path
            }
        } catch {}

        return nil
    }
}
