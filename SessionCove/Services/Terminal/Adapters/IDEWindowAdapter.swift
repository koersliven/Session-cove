import AppKit
import Foundation

/// Adapter for IDE-hosted integrated terminals (VS Code, Cursor).
///
/// Electron apps have almost no AppleScript dictionary — `activate` is the
/// only reliable operation. To focus the correct workspace window we use the
/// `code` CLI (`code <path> --reuse-window`), which opens the project folder
/// in the already-running VSCode instance. This brings the user to the exact
/// window where their Claude Code session lives.
///
/// We never *launch* a fresh agent into an IDE integrated terminal — that
/// path stays with the real terminal adapters — so `launch` is unsupported.
struct IDEWindowAdapter: TerminalAdapter {
    let kind: TerminalKind

    var isInstalled: Bool {
        TerminalAdapterHelpers.isAppInstalled(bundleID: kind.bundleID)
    }

    /// Bring the IDE window to the front, then try to open the project
    /// workspace via CLI so the correct VSCode/Cursor window surfaces.
    func focusSession(tty: String) -> Bool {
        let activated = TerminalAdapterHelpers.activateRunningApp(bundleID: kind.bundleID)
        return activated
    }

    /// Focus the specific project workspace in the IDE. Call this *after*
    /// `focusSession` when you know the project path.
    static func focusWorkspace(path: String, kind: TerminalKind) -> Bool {
        let cliPath = Self.cliBinaryPath(for: kind)
        guard let cli = cliPath, FileManager.default.isExecutableFile(atPath: cli) else {
            return false
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cli)
        process.arguments = [path, "--reuse-window"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard let _ = try? process.run() else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private static func cliBinaryPath(for kind: TerminalKind) -> String? {
        switch kind {
        case .vscode:
            let candidates = [
                "/usr/local/bin/code",
                "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
            ]
            return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
        case .cursor:
            let candidates = [
                "/usr/local/bin/cursor",
                "/Applications/Cursor.app/Contents/Resources/app/bin/cursor"
            ]
            return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
        default:
            return nil
        }
    }

    func launch(command: String, cwd: String) throws {
        throw TerminalAdapterError.unsupportedOperation(
            kind,
            "launch into an IDE integrated terminal"
        )
    }
}
