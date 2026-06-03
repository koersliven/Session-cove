import AppKit
import Foundation

// MARK: - TerminalKind

enum TerminalKind: String, Codable, CaseIterable, Sendable {
    case iterm
    case terminalApp
    case ghostty
    case warp
    case alacritty
    case kitty
    case wezterm

    var displayName: String {
        switch self {
        case .iterm:        return "iTerm2"
        case .terminalApp:  return "Terminal"
        case .ghostty:      return "Ghostty"
        case .warp:         return "Warp"
        case .alacritty:    return "Alacritty"
        case .kitty:        return "kitty"
        case .wezterm:      return "WezTerm"
        }
    }

    var bundleID: String {
        switch self {
        case .iterm:        return "com.googlecode.iterm2"
        case .terminalApp:  return "com.apple.Terminal"
        case .ghostty:      return "com.mitchellh.ghostty"
        case .warp:         return "dev.warp.Warp-Stable"
        case .alacritty:    return "org.alacritty"
        case .kitty:        return "net.kovidgoyal.kitty"
        case .wezterm:      return "com.github.wez.wezterm"
        }
    }

    /// Default CLI binary path/name for the terminal. `nil` when the terminal
    /// has no CLI worth shelling out to (Warp, Terminal.app — those go through
    /// AppleScript or `open`).
    var defaultBinaryPath: String? {
        switch self {
        case .iterm:        return nil // AppleScript only
        case .terminalApp:  return nil // AppleScript / `open`
        case .ghostty:      return nil // launched via `open -na Ghostty`
        case .warp:         return nil // launched via URL scheme
        case .alacritty:    return "/opt/homebrew/bin/alacritty"
        case .kitty:        return "/Applications/kitty.app/Contents/MacOS/kitty"
        case .wezterm:      return "/opt/homebrew/bin/wezterm"
        }
    }
}

// MARK: - Errors

enum TerminalAdapterError: Error, CustomStringConvertible {
    case notInstalled(TerminalKind)
    case unsupportedOperation(TerminalKind, String)
    case processFailed(TerminalKind, String)
    case appleScriptFailed(TerminalKind, String)

    var description: String {
        switch self {
        case .notInstalled(let kind):
            return "[\(kind.rawValue)] not installed"
        case .unsupportedOperation(let kind, let op):
            return "[\(kind.rawValue)] does not support \(op)"
        case .processFailed(let kind, let msg):
            return "[\(kind.rawValue)] process failed: \(msg)"
        case .appleScriptFailed(let kind, let msg):
            return "[\(kind.rawValue)] AppleScript failed: \(msg)"
        }
    }
}

// MARK: - TerminalAdapter Protocol

/// Per-terminal abstraction for focusing an existing TTY or launching a new
/// session. `focusSession` returns `false` when the adapter cannot resolve the
/// TTY (or the operation is unsupported); the caller should then try the next
/// adapter or fall back to `launch`.
protocol TerminalAdapter {
    var kind: TerminalKind { get }
    var isInstalled: Bool { get }

    /// Try to focus the terminal window/tab/pane that owns `tty`. Returns
    /// `true` when the terminal was activated and the target session
    /// brought to front.
    func focusSession(tty: String) -> Bool

    /// Open a new window/tab/pane in `cwd` and run `command`. Throws on
    /// hard failure (process couldn't start, AppleScript error, etc.).
    func launch(command: String, cwd: String) throws
}

// MARK: - TerminalAdapterHelpers

/// Shared utilities used by every adapter. Standalone (no SessionResumer
/// dependency) so adapters can compile independently. The legacy
/// implementations in `SessionResumer.swift` stay intact until the wire phase
/// migrates them.
enum TerminalAdapterHelpers {

    // MARK: AppleScript

    enum AppleScriptResult {
        case success(String)
        case failure(String)
    }

    /// Synchronously run an AppleScript via `osascript` with a 5 s timeout.
    /// Without the timeout, osascript blocks indefinitely while macOS shows a
    /// TCC ("automation permission") dialog — and the pet-mode floating panel
    /// often *covers* that dialog so the user never sees it, producing the
    /// "spinner forever" symptom. Run this off the main thread.
    static func appleScriptResult(_ source: String, timeout: TimeInterval = 5.0) -> AppleScriptResult {
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

        let deadline = DispatchTime.now() + timeout
        let queue = DispatchQueue.global(qos: .userInitiated)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        let lock = NSLock()
        var timedOut = false
        timer.schedule(deadline: deadline)
        timer.setEventHandler {
            lock.lock()
            if process.isRunning {
                timedOut = true
                process.terminate()
            }
            lock.unlock()
        }
        timer.resume()

        process.waitUntilExit()
        timer.cancel()

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if timedOut {
            return .failure("osascript timed out after \(Int(timeout))s (likely a TCC permission dialog the user can't see)")
        }

        if process.terminationStatus != 0 {
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8) ?? ""
            return .failure("osascript exit \(process.terminationStatus): \(errStr)")
        }
        return .success(output)
    }

    // MARK: Shell helpers

    /// Quote a path/argument for safe inclusion in a shell command (single-quoted).
    static func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Escape a string for embedding inside an AppleScript double-quoted literal.
    static func appleScriptEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    // MARK: Process runner

    struct ProcessOutput {
        let exitStatus: Int32
        let stdout: String
        let stderr: String

        var didSucceed: Bool { exitStatus == 0 }
    }

    /// Run a process synchronously with a 5-second timeout. Returns the
    /// captured output on completion. Throws `TerminalAdapterError.processFailed`
    /// when the process fails to launch or hangs past the timeout.
    @discardableResult
    static func runProcess(
        _ executable: String,
        arguments: [String],
        kind: TerminalKind,
        timeout: TimeInterval = 5.0,
        environment: [String: String]? = nil
    ) throws -> ProcessOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let env = environment { process.environment = env }
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw TerminalAdapterError.processFailed(kind, "spawn failed: \(error)")
        }

        // Enforce timeout via DispatchSourceTimer so we never hang the caller.
        let deadline = DispatchTime.now() + timeout
        let queue = DispatchQueue.global(qos: .userInitiated)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        let didTimeout = NSLock()
        var timedOut = false
        timer.schedule(deadline: deadline)
        timer.setEventHandler {
            didTimeout.lock()
            if process.isRunning {
                timedOut = true
                process.terminate()
            }
            didTimeout.unlock()
        }
        timer.resume()

        process.waitUntilExit()
        timer.cancel()

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        let outStr = String(data: outData, encoding: .utf8) ?? ""
        let errStr = String(data: errData, encoding: .utf8) ?? ""

        if timedOut {
            throw TerminalAdapterError.processFailed(
                kind,
                "timed out after \(Int(timeout))s: \(executable) \(arguments.joined(separator: " "))"
            )
        }

        return ProcessOutput(
            exitStatus: process.terminationStatus,
            stdout: outStr,
            stderr: errStr
        )
    }

    // MARK: Installed detection

    /// Returns true when the bundle is registered with Launch Services.
    static func isAppInstalled(bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    /// Best-effort "bring the running terminal app to the foreground" —
    /// for adapters without a scripting bridge that can target a specific
    /// tab/tty (Ghostty / Warp / Alacritty). Strictly better than the
    /// previous always-false → launch-fallback path, which would have
    /// spawned a fresh `claude --resume` and duplicated the session.
    /// Returns false when no running instance exists, in which case the
    /// caller falls back to the next adapter in the focus chain.
    static func activateRunningApp(bundleID: String) -> Bool {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        guard let app = running.first else { return false }
        if #available(macOS 14.0, *) {
            return app.activate()
        } else {
            return app.activate(options: [.activateAllWindows])
        }
    }

    /// Returns true when a CLI binary exists on disk and is executable.
    static func isExecutablePresent(_ path: String) -> Bool {
        let fm = FileManager.default
        return fm.isExecutableFile(atPath: path)
    }

    // MARK: TTY normalization

    /// Returns the `/dev/ttysNNN` form (with leading `/dev/`).
    static func fullTTY(_ tty: String) -> String {
        tty.hasPrefix("/dev/") ? tty : "/dev/\(tty)"
    }

    /// Returns the bare `ttysNNN` form (no leading `/dev/`).
    static func shortTTY(_ tty: String) -> String {
        tty.replacingOccurrences(of: "/dev/", with: "")
    }
}
