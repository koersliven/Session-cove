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
                    focusITermSessionByTTY(tty: tty, fallbackSession: session)
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
        process.arguments = ["-eo", "tty=,args="]
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

        guard process.terminationStatus == 0 else { return nil }
        guard let output = String(data: data, encoding: .utf8) else { return nil }

        for line in output.components(separatedBy: "\n") {
            guard line.contains("claude") else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Match by session ID in args
            if trimmed.contains(session.id) {
                let tty = String(trimmed.prefix(while: { !$0.isWhitespace }))
                if !tty.isEmpty && tty != "??" {
                    return tty
                }
            }
        }
        return nil
    }

    /// Try to focus the iTerm2 tab with matching TTY. If it fails, launch new session.
    private static func focusITermSessionByTTY(tty: String, fallbackSession: SessionRecord) {
        let fullTTY = tty.hasPrefix("/dev/") ? tty : "/dev/\(tty)"
        let shortTTY = tty.replacingOccurrences(of: "/dev/", with: "")

        // Use the verified-working iTerm2 focus pattern:
        // select theTab → select theSession → select resolvedWindow → activate
        // Do NOT use "set frontmost of theWindow to true" (causes error -10000)
        let script = """
        tell application "iTerm2"
            repeat with theWindow in windows
                repeat with theTab in tabs of theWindow
                    repeat with theSession in sessions of theTab
                        set sessionTTY to tty of theSession
                        if sessionTTY is "\(fullTTY)" or sessionTTY is "\(shortTTY)" then
                            set targetWindowId to (id of theWindow)
                            set resolvedWindow to first window whose id is targetWindowId
                            select theTab
                            select theSession
                            select resolvedWindow
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
                print("[SessionResumer] Session not found in iTerm2 (returned: \(value)), launching new")
                launchNewSession(session: fallbackSession)
            }
        case .failure(let errorDesc):
            print("[SessionResumer] Focus script failed: \(errorDesc), launching new session")
            launchNewSession(session: fallbackSession)
        }
    }

    private static func launchNewSession(session: SessionRecord) {
        let command = "cd \(shellEscape(session.projectPath)) && claude --resume \(session.id)"
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

        print("[SessionResumer] Launching new iTerm2 session for: \(session.id)")
        let result = executeAppleScript(script)

        switch result {
        case .success:
            print("[SessionResumer] Successfully launched new iTerm2 session")
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
        guard let appleScript = NSAppleScript(source: source) else {
            return .failure("Failed to create NSAppleScript instance")
        }

        var errorDict: NSDictionary?
        let descriptor = appleScript.executeAndReturnError(&errorDict)

        if let errorDict {
            let errorMessage = errorDict[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            let errorNumber = errorDict[NSAppleScript.errorNumber] as? Int ?? -1
            return .failure("[\(errorNumber)] \(errorMessage)")
        }

        return .success(descriptor.stringValue ?? "")
    }

    private static func shellEscape(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
