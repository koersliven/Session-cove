import AppKit

struct SessionResumer {
    static func resume(session: SessionRecord) {
        print("[SessionResumer] resume called for session: \(session.id) project: \(session.projectPath)")

        // Run TTY lookup on background thread, then execute AppleScript on main thread.
        // NSAppleScript must run on the main thread.
        DispatchQueue.global(qos: .userInitiated).async {
            let tty = findSessionTTY(session: session)
            print("[SessionResumer] TTY lookup result: \(tty ?? "nil")")

            DispatchQueue.main.async {
                if let tty {
                    focusITermSessionByTTY(tty: tty)
                } else {
                    launchNewSession(session: session)
                }
            }
        }
    }

    private static func findSessionTTY(session: SessionRecord) -> String? {
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
                return tty
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
                return tty
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

    private static func focusITermSessionByTTY(tty: String) {
        let fullTTY = tty.hasPrefix("/dev/") ? tty : "/dev/\(tty)"
        let shortTTY = tty.replacingOccurrences(of: "/dev/", with: "")

        let script = """
        tell application "iTerm2"
            repeat with theWindow in windows
                repeat with theTab in tabs of theWindow
                    repeat with theSession in sessions of theTab
                        set sessionTTY to tty of theSession
                        if sessionTTY is "\(fullTTY)" or sessionTTY is "\(shortTTY)" then
                            select theTab
                            select theSession
                            select (first window whose id is (id of theWindow))
                            activate
                            return "ok"
                        end if
                    end repeat
                end repeat
            end repeat
            return "not-found"
        end tell
        """

        print("[SessionResumer] Executing focus script for TTY: \(fullTTY)")
        let result = executeAppleScript(script)

        switch result {
        case .success(let value):
            if value == "ok" {
                print("[SessionResumer] Successfully focused iTerm2 session")
            } else {
                print("[SessionResumer] TTY not found in iTerm2, bringing iTerm to front")
                bringITermToFront()
            }
        case .failure:
            print("[SessionResumer] Focus script failed (TCC?), bringing iTerm to front")
            bringITermToFront()
        }
    }

    private static func bringITermToFront() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "iTerm"]
        try? process.run()
        process.waitUntilExit()
    }

    private static func launchNewSession(session: SessionRecord) {
        let command = "cd \(shellEscape(session.projectPath)) && claude --resume \(session.id)"
        print("[SessionResumer] Launching new iTerm2 session for: \(session.id)")
        launchInNewWindow(command: command)
    }

    static func launchNew(projectPath: String) {
        let command = "cd \(shellEscape(projectPath)) && claude"
        print("[SessionResumer] Launching new Claude session in: \(projectPath)")
        launchInNewWindow(command: command)
    }

    private static func launchInNewWindow(command: String) {
        let escapedCommand = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application "iTerm2"
            activate
            set newWindow to (create window with default profile)
            tell current session of newWindow
                write text "\(escapedCommand)"
            end tell
        end tell
        """

        let result = executeAppleScript(script)
        switch result {
        case .success:
            print("[SessionResumer] Successfully launched new iTerm2 window")
        case .failure(let errorDesc):
            print("[SessionResumer] iTerm2 launch failed: \(errorDesc), trying Terminal.app")
            openInTerminal(command: command)
        }
    }

    private static func openInTerminal(command: String) {
        let escapedCommand = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application "Terminal"
            activate
            do script "\(escapedCommand)"
        end tell
        """

        let result = executeAppleScript(script)
        switch result {
        case .success:
            print("[SessionResumer] Successfully launched Terminal.app session")
        case .failure(let errorDesc):
            print("[SessionResumer] Terminal.app also failed: \(errorDesc)")
        }
    }

    // MARK: - Helpers

    private enum ScriptResult {
        case success(String)
        case failure(String)
    }

    private static func executeAppleScript(_ source: String) -> ScriptResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return .failure("Failed to launch osascript: \(error)")
        }

        process.waitUntilExit()
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if process.terminationStatus != 0 {
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8) ?? ""
            return .failure("osascript exit \(process.terminationStatus): \(errStr)")
        }

        return .success(output)
    }

    private static func shellEscape(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
