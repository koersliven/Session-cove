import Foundation

/// iTerm2 — the legacy "golden path" adapter. Uses AppleScript for both
/// focusing an existing TTY and launching new windows. Logic mirrors
/// `SessionResumer.focusITermSession` / `launchInNewWindow` (which still
/// owns the runtime call sites until the wire phase migrates).
struct ITermAdapter: TerminalAdapter {
    let kind: TerminalKind = .iterm

    var isInstalled: Bool {
        TerminalAdapterHelpers.isAppInstalled(bundleID: kind.bundleID)
    }

    func focusSession(tty: String) -> Bool {
        let fullTTY = TerminalAdapterHelpers.fullTTY(tty)
        let shortTTY = TerminalAdapterHelpers.shortTTY(tty)

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

        switch TerminalAdapterHelpers.appleScriptResult(script) {
        case .success(let value):
            return value == "ok"
        case .failure(let err):
            print("[ITermAdapter] focus failed: \(err)")
            return false
        }
    }

    /// Write text to the iTerm2 session identified by `tty` WITHOUT activating
    /// or selecting the window — the text is delivered in the background so the
    /// user stays in the Session Cove popup. Falls back to the POSIX default if
    /// the AppleScript fails.
    func writeText(tty: String, text: String) -> Bool {
        let fullTTY = TerminalAdapterHelpers.fullTTY(tty)
        let shortTTY = TerminalAdapterHelpers.shortTTY(tty)
        let escapedText = TerminalAdapterHelpers.appleScriptEscape(text)

        let script = """
        tell application "iTerm2"
            repeat with theWindow in windows
                repeat with theTab in tabs of theWindow
                    repeat with theSession in sessions of theTab
                        set sessionTTY to tty of theSession
                        if sessionTTY is "\(fullTTY)" or sessionTTY is "\(shortTTY)" then
                            tell theSession to write text "\(escapedText)" newline no
                            delay 0.2
                            tell theSession to write text ""
                            return "ok"
                        end if
                    end repeat
                end repeat
            end repeat
            return "not-found"
        end tell
        """

        switch TerminalAdapterHelpers.appleScriptResult(script) {
        case .success(let value):
            return value == "ok"
        case .failure(let err):
            print("[ITermAdapter] writeText AppleScript failed: \(err), falling back to POSIX")
            // Fall back to universal POSIX tty write
            let fullPath = TerminalAdapterHelpers.fullTTY(tty)
            guard let data = (text + "\n").data(using: .utf8),
                  let handle = FileHandle(forWritingAtPath: fullPath) else { return false }
            defer { handle.closeFile() }
            handle.write(data)
            return true
        }
    }

    func launch(command: String, cwd: String) throws {
        let composed = "cd \(TerminalAdapterHelpers.shellEscape(cwd)) && \(command)"
        let escaped = TerminalAdapterHelpers.appleScriptEscape(composed)

        let script = """
        tell application "iTerm2"
            activate
            set newWindow to (create window with default profile)
            tell current session of newWindow
                write text "\(escaped)"
            end tell
        end tell
        """

        switch TerminalAdapterHelpers.appleScriptResult(script) {
        case .success:
            return
        case .failure(let err):
            throw TerminalAdapterError.appleScriptFailed(kind, err)
        }
    }
}
