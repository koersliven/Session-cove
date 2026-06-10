import Foundation

/// Delivers answer text to a running Claude session's terminal by typing it
/// directly into the tty — as if the user had typed the answer at the terminal
/// prompt. This bypasses the fragile hook-stdout path (`updatedInput`) and
/// instead relies on Claude rendering its built-in terminal question prompt
/// while the Python bridge stays silent.
///
/// Flow:
/// 1. Look up the session's tty+pid via SessionResumer's ps/lsof logic.
/// 2. Determine which terminal owns the pid (iTerm/kitty/WezTerm/etc).
/// 3. Call that adapter's `writeText(tty:text:)` method.
/// 4. Fall back to POSIX `/dev/ttysNNN` write if adapter-specific fails.
///
/// All work runs on a background DispatchQueue. Callers fire-and-forget.
enum TerminalTextInjector {

    /// Delay between the Python bridge exiting (unblocking Claude to render the
    /// terminal prompt) and our text injection. Gives the terminal time to
    /// display the prompt so our injected text lands in the right readline state.
    /// 1500ms is the sweet spot: PermissionRequest emit allow unblocks Claude
    /// immediately, prompt renders in ~500-800ms, stdin read ready by ~1000ms.
    /// Too long (5s) and Claude's streaming response starts rendering and
    /// overwrites the prompt. Too short (300ms) and prompt isn't ready yet.
    static let injectionDelayMs: Int = 1500

    // MARK: - Public

    /// Inject answer text into the terminal hosting the given session.
    /// Returns immediately; the actual injection happens asynchronously after
    /// `injectionDelayMs`. The completion closure fires on a background queue
    /// with `true` on success, `false` on failure (caller can trigger fallback).
    @discardableResult
    static func injectAnswer(
        sessionId: String?,
        projectPath: String,
        questions: [HookInterventionQuestion],
        answers: [String: String],
        completion: ((Bool) -> Void)? = nil
    ) -> Bool {
        let text = answerTextForTerminal(questions: questions, answers: answers)
        guard !text.isEmpty else {
            print("[TerminalTextInjector] empty answer text, skipping injection")
            completion?(false)
            return false
        }

        DispatchQueue.global(qos: .userInitiated).async {
            // Wait for Claude to render its terminal prompt
            Thread.sleep(forTimeInterval: Double(injectionDelayMs) / 1000.0)

            let success = performInjection(
                sessionId: sessionId,
                projectPath: projectPath,
                text: text
            )
            logInjection(success: success, text: text, sessionId: sessionId, projectPath: projectPath)
            completion?(success)
        }

        return true // "scheduled" — actual result comes via completion
    }

    // MARK: - Answer Text Conversion

    /// Convert the HookQuestionView submission payload (`[questionId: answer]`)
    /// into the exact text string that Claude expects at its terminal prompt.
    ///
    /// Claude's terminal UX for questions:
    /// - Single-select with options: numbered list (1, 2, 3...). User types a number.
    /// - Multi-select: numbered list. User types comma-separated numbers (e.g. "1,3").
    /// - Free-text (no options): user types their answer verbatim.
    ///
    /// When multiple questions exist, Claude asks them sequentially — each answer
    /// is followed by Enter. We return the text for the FIRST unanswered question
    /// only (Claude will re-fire the hook for subsequent questions if needed).
    /// In practice, AskUserQuestion typically carries a single question.
    static func answerTextForTerminal(
        questions: [HookInterventionQuestion],
        answers: [String: String]
    ) -> String {
        guard let question = questions.first,
              let answer = answers[question.id] else {
            return ""
        }

        // Free-text question (no options) — return verbatim
        if question.options.isEmpty {
            return answer
        }

        // Option-based question: answer contains comma-separated option IDs
        // (e.g. "us-east" or "api,ui"). Map each ID back to its 1-based index.
        let selectedIds = answer.split(separator: ",").map(String.init)
        var indices: [Int] = []

        for selectedId in selectedIds {
            let trimmed = selectedId.trimmingCharacters(in: .whitespaces)
            if let idx = question.options.firstIndex(where: { $0.id == trimmed }) {
                indices.append(idx + 1) // 1-based
            } else {
                // Not a known option id — could be "Other..." free text.
                // For "Other", Claude typically presents it as the last numbered
                // option. If we can't map it, return it as free text (the user
                // typed something custom).
                return trimmed
            }
        }

        if indices.isEmpty {
            return answer // fallback: pass through verbatim
        }

        if question.allowsMultiple {
            return indices.map(String.init).joined(separator: ",")
        } else {
            return String(indices[0])
        }
    }

    // MARK: - Private

    private static func performInjection(
        sessionId: String?,
        projectPath: String,
        text: String
    ) -> Bool {
        // 1. Look up the session's tty
        guard let lookup = findSessionTTY(sessionId: sessionId ?? "", projectPath: projectPath) else {
            print("[TerminalTextInjector] tty lookup failed for session=\(sessionId?.prefix(12) ?? "nil") project=\(projectPath)")
            return false
        }

        let tty = lookup.tty
        let pid = lookup.pid
        print("[TerminalTextInjector] found tty=\(tty) pid=\(pid)")

        // 2. Determine which terminal owns this pid
        let adapter: TerminalAdapter
        if let kind = TerminalDetector.ancestorTerminal(of: pid),
           let resolved = adapterFor(kind),
           resolved.isInstalled {
            adapter = resolved
        } else {
            // Use the general resolved terminal (iTerm > Terminal.app > etc)
            adapter = TerminalDetector.resolvedTerminal()
        }

        // 3. Try adapter-specific writeText
        print("[TerminalTextInjector] injecting via \(adapter.kind.displayName)")
        let success = adapter.writeText(tty: tty, text: text)

        if !success {
            // 4. Fallback: universal POSIX tty write
            print("[TerminalTextInjector] adapter writeText failed, trying POSIX fallback")
            return posixWriteText(tty: tty, text: text)
        }

        return success
    }

    /// Universal POSIX fallback: open the tty device and write directly.
    private static func posixWriteText(tty: String, text: String) -> Bool {
        let fullPath = TerminalAdapterHelpers.fullTTY(tty)
        guard let data = (text + "\n").data(using: .utf8) else { return false }
        guard let handle = FileHandle(forWritingAtPath: fullPath) else {
            print("[TerminalTextInjector] POSIX: cannot open \(fullPath)")
            return false
        }
        defer { handle.closeFile() }
        handle.write(data)
        return true
    }

    /// TTY lookup — reuses SessionResumer's logic. We can't call
    /// `SessionResumer.findSessionTTY` directly because it's private, so we
    /// duplicate the minimal ps+lsof lookup here. Same algorithm as
    /// SessionResumer.findSessionTTY but exposed for our use.
    private static func findSessionTTY(sessionId: String, projectPath: String) -> (tty: String, pid: Int32)? {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,tty=,comm=,args="]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do { try process.run() } catch { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8) else { return nil }

        let agentBinaries = enabledAgentBinaries()
        let agentBinarySet = Set(agentBinaries)
        var agentPidTty: [(pid: Int32, tty: String)] = []

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 4, let pid = Int32(parts[0]) else { continue }
            let tty = parts[1]
            guard tty != "??" else { continue }
            let commName = (parts[2] as NSString).lastPathComponent
            let argsJoined = parts[3..<parts.count].joined(separator: " ")

            // Phase 1: args contain the session id
            if !sessionId.isEmpty, argsJoined.contains(sessionId) {
                return (tty, pid)
            }

            if agentBinarySet.contains(commName) {
                agentPidTty.append((pid, tty))
            }
        }

        // Phase 2: cwd match
        let targetCwd = normalizePath(projectPath)
        for entry in agentPidTty {
            if let cwd = lsofCwd(pid: entry.pid), normalizePath(cwd) == targetCwd {
                return (tty: entry.tty, pid: entry.pid)
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
        while p.count > 1 && p.hasSuffix("/") { p = String(p.dropLast()) }
        return p
    }

    private static func enabledAgentBinaries() -> [String] {
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

    private static func adapterFor(_ kind: TerminalKind) -> TerminalAdapter? {
        switch kind {
        case .iterm:        return ITermAdapter()
        case .terminalApp:  return TerminalAppAdapter()
        case .ghostty:      return GhosttyAdapter()
        case .kitty:        return KittyAdapter()
        case .wezterm:      return WezTermAdapter()
        case .alacritty:    return AlacrittyAdapter()
        case .warp:         return nil
        // IDE integrated terminals have no scriptable text-injection path;
        // their host app owns the prompt. Returning nil falls back to the
        // POSIX tty write in the caller (or no-op).
        case .vscode, .cursor: return nil
        }
    }

    // MARK: - Logging

    private static func logInjection(success: Bool, text: String, sessionId: String?, projectPath: String) {
        let logPath = "/tmp/session-cove.log"
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let preview = String(text.prefix(80)).replacingOccurrences(of: "\n", with: "\\n")
        let line = "[\(timestamp)] TerminalTextInjector: success=\(success) session=\(sessionId?.prefix(12) ?? "nil") project=\(projectPath) text=\"\(preview)\"\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath) {
                if let handle = FileHandle(forWritingAtPath: logPath) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                FileManager.default.createFile(atPath: logPath, contents: data)
            }
        }
    }
}
