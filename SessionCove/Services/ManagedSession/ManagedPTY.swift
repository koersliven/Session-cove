import Foundation
import Darwin

/// Low-level wrapper around POSIX `forkpty()`. Spawns a child process attached
/// to a pseudo-terminal and exposes the master fd for reading (child stdout) and
/// writing (child stdin injection).
///
/// This class is intentionally NOT `@MainActor` -- all pty I/O happens on
/// background queues. Callers must dispatch to `@MainActor` themselves if they
/// need to update UI state from output callbacks.
///
/// Lifecycle: call `spawn(...)` to create a live instance, then `read()` /
/// `write(_:)` to communicate. `kill()` or `deinit` sends SIGHUP to the child
/// and closes the master fd.
final class ManagedPTY: @unchecked Sendable {

    // MARK: - Properties

    /// Master file descriptor of the pty pair. Reads yield child stdout;
    /// writes inject into child stdin.
    private(set) var masterFD: Int32 = -1

    /// PID of the child process.
    private(set) var childPID: pid_t = 0

    /// Session identifier (passed through from the caller for bookkeeping).
    let sessionId: String

    /// Whether the child process is still running.
    var isAlive: Bool {
        guard childPID > 0 else { return false }
        // waitpid with WNOHANG: 0 = still running, >0 = exited, -1 = error
        var status: Int32 = 0
        let result = waitpid(childPID, &status, WNOHANG)
        return result == 0
    }

    // MARK: - Init (private -- use spawn())

    private init(sessionId: String) {
        self.sessionId = sessionId
    }

    deinit {
        cleanup()
    }

    // MARK: - Factory

    /// Spawn a child process inside a new pty.
    ///
    /// - Parameters:
    ///   - command: Absolute path to the executable (e.g. `/usr/local/bin/claude`).
    ///   - args: Argument vector (argv[0] should be the binary name by convention).
    ///   - cwd: Working directory for the child.
    ///   - env: Optional environment overrides merged onto the current process env.
    ///   - sessionId: Identifier for bookkeeping (not passed to the child).
    ///   - cols: Initial terminal width.
    ///   - rows: Initial terminal height.
    /// - Returns: A live `ManagedPTY` instance, or `nil` if fork/exec failed.
    static func spawn(
        command: String,
        args: [String],
        cwd: String,
        env: [String: String]? = nil,
        sessionId: String,
        cols: Int = 120,
        rows: Int = 30
    ) -> ManagedPTY? {
        let instance = ManagedPTY(sessionId: sessionId)

        // Prepare winsize struct
        var ws = winsize()
        ws.ws_col = UInt16(cols)
        ws.ws_row = UInt16(rows)
        ws.ws_xpixel = 0
        ws.ws_ypixel = 0

        // forkpty: creates pty pair, forks, child gets slave as controlling tty
        var masterFD: Int32 = -1
        let pid = forkpty(&masterFD, nil, nil, &ws)

        if pid < 0 {
            // forkpty failed
            print("[ManagedPTY] forkpty failed: \(String(cString: strerror(errno)))")
            return nil
        }

        if pid == 0 {
            // ---- Child process ----
            // Change working directory
            if chdir(cwd) != 0 {
                // If chdir fails, still try to exec (will run in parent's cwd)
                fputs("[ManagedPTY:child] chdir failed: \(cwd)\n", stderr)
            }

            // Build environment
            var childEnv = ProcessInfo.processInfo.environment
            childEnv["TERM"] = "xterm-256color"
            childEnv["COLORTERM"] = "truecolor"
            if let overrides = env {
                for (key, value) in overrides {
                    childEnv[key] = value
                }
            }

            // Convert to C-style envp
            let envp: [UnsafeMutablePointer<CChar>?] = childEnv.map { key, value in
                strdup("\(key)=\(value)")
            } + [nil]

            // Convert args to C-style argv
            let argv: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) } + [nil]

            // exec
            execve(command, argv, envp)

            // If execve returns, it failed
            fputs("[ManagedPTY:child] execve failed: \(String(cString: strerror(errno)))\n", stderr)
            _exit(127)
        }

        // ---- Parent process ----
        instance.masterFD = masterFD
        instance.childPID = pid

        // Set master fd to non-blocking for read()
        let flags = fcntl(masterFD, F_GETFL)
        if flags >= 0 {
            _ = fcntl(masterFD, F_SETFL, flags | O_NONBLOCK)
        }

        return instance
    }

    // MARK: - I/O

    /// Non-blocking read from the master fd. Returns whatever bytes are
    /// currently available (may be empty if the child hasn't produced output).
    /// Returns `nil` on read error (fd closed, child exited).
    func read() -> Data? {
        guard masterFD >= 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: 8192)
        let bytesRead = Darwin.read(masterFD, &buffer, buffer.count)

        if bytesRead > 0 {
            return Data(buffer[0..<bytesRead])
        } else if bytesRead == 0 {
            // EOF -- child closed its side
            return nil
        } else {
            // bytesRead < 0
            if errno == EAGAIN || errno == EWOULDBLOCK {
                // No data available right now (non-blocking)
                return Data()
            }
            // Real error
            return nil
        }
    }

    /// Write raw bytes to the master fd (appears as stdin to the child).
    @discardableResult
    func write(_ data: Data) -> Bool {
        guard masterFD >= 0 else { return false }
        return data.withUnsafeBytes { rawBuffer -> Bool in
            guard let baseAddress = rawBuffer.baseAddress else { return false }
            var totalWritten = 0
            let count = data.count
            while totalWritten < count {
                let written = Darwin.write(
                    masterFD,
                    baseAddress.advanced(by: totalWritten),
                    count - totalWritten
                )
                if written <= 0 {
                    if errno == EAGAIN || errno == EWOULDBLOCK {
                        // Retry after brief yield
                        usleep(1000)
                        continue
                    }
                    return false
                }
                totalWritten += written
            }
            return true
        }
    }

    /// Convenience: write a UTF-8 string to the child's stdin.
    @discardableResult
    func write(_ string: String) -> Bool {
        guard let data = string.data(using: .utf8) else { return false }
        return write(data)
    }

    // MARK: - Terminal Control

    /// Resize the pty window. The child receives SIGWINCH.
    func resize(cols: Int, rows: Int) {
        guard masterFD >= 0 else { return }
        var ws = winsize()
        ws.ws_col = UInt16(cols)
        ws.ws_row = UInt16(rows)
        ws.ws_xpixel = 0
        ws.ws_ypixel = 0
        _ = ioctl(masterFD, TIOCSWINSZ, &ws)
    }

    // MARK: - Lifecycle

    /// Send SIGHUP to the child and close the master fd.
    func kill() {
        cleanup()
    }

    private func cleanup() {
        if childPID > 0 {
            Darwin.kill(childPID, SIGHUP)
            // Give child a moment to exit, then force-kill
            var status: Int32 = 0
            let result = waitpid(childPID, &status, WNOHANG)
            if result == 0 {
                // Still alive after SIGHUP, schedule a SIGKILL
                DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) { [pid = self.childPID] in
                    var s: Int32 = 0
                    if waitpid(pid, &s, WNOHANG) == 0 {
                        Darwin.kill(pid, SIGKILL)
                        waitpid(pid, &s, 0)
                    }
                }
            }
            childPID = 0
        }
        if masterFD >= 0 {
            close(masterFD)
            masterFD = -1
        }
    }
}
