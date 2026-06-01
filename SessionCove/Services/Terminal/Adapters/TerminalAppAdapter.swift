import Foundation

/// Apple Terminal.app — fallback golden path. AppleScript exposes `tty` on
/// each tab directly (full path form, e.g. `/dev/ttys003`).
struct TerminalAppAdapter: TerminalAdapter {
    let kind: TerminalKind = .terminalApp

    var isInstalled: Bool {
        // Terminal.app is bundled with macOS — bundle lookup may still fail in
        // sandboxed contexts so we treat it as always-present.
        true
    }

    func focusSession(tty: String) -> Bool {
        let fullTTY = TerminalAdapterHelpers.fullTTY(tty)

        let script = """
        tell application "Terminal"
            repeat with theWindow in windows
                repeat with theTab in tabs of theWindow
                    if tty of theTab is "\(fullTTY)" then
                        set selected tab of theWindow to theTab
                        set frontmost of theWindow to true
                        activate
                        return "ok"
                    end if
                end repeat
            end repeat
            return "not-found"
        end tell
        """

        switch TerminalAdapterHelpers.appleScriptResult(script) {
        case .success(let value):
            return value == "ok"
        case .failure(let err):
            print("[TerminalAppAdapter] focus failed: \(err)")
            return false
        }
    }

    func launch(command: String, cwd: String) throws {
        let composed = "cd \(TerminalAdapterHelpers.shellEscape(cwd)) && \(command)"
        let escaped = TerminalAdapterHelpers.appleScriptEscape(composed)

        let script = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
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
