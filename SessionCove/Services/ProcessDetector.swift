import Foundation

final class ProcessDetector: @unchecked Sendable {
    static let shared = ProcessDetector()

    /// Collect cwds of running `claude` processes.
    /// If the user kills claude, the session stops being active — they re-RESUME.
    func detectActiveProjectPaths() -> Set<String> {
        let pids = listClaudePids()
        guard !pids.isEmpty else { return [] }
        return collectCwds(pids: pids)
    }

    /// cwd hit on island.path → mark the island's most-recent session active.
    /// SessionScanner already sorts sessions by lastModified desc, so sessions[0] is newest.
    func applyStatuses(activeProjectPaths: Set<String>, to islands: inout [ProjectIsland]) {
        let now = Date()
        let recentThreshold: TimeInterval = 24 * 60 * 60
        let normalized = Set(activeProjectPaths.map(Self.normalize))

        for i in islands.indices {
            let islandActive = normalized.contains(Self.normalize(islands[i].path))
            for j in islands[i].sessions.indices {
                let session = islands[i].sessions[j]
                if islandActive && j == 0 {
                    islands[i].sessions[j].status = .active
                } else if now.timeIntervalSince(session.lastModified) < recentThreshold {
                    islands[i].sessions[j].status = .recentlyIdle
                } else {
                    islands[i].sessions[j].status = .archived
                }
            }
        }
    }

    // MARK: - Private

    private func listClaudePids() -> [Int32] {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,comm="]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            print("[ProcessDetector] ps failed: \(error)")
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8) else { return [] }

        var pids: [Int32] = []
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 2, let pid = Int32(parts[0]) else { continue }

            // comm column may contain a path; take the basename and match `claude` exactly.
            let commName = (parts[1..<parts.count].joined(separator: " ") as NSString).lastPathComponent
            if commName == "claude" {
                pids.append(pid)
            }
        }
        return pids
    }

    /// One `lsof` call for all pids — `-F n` emits `n<path>` lines for cwd.
    private func collectCwds(pids: [Int32]) -> Set<String> {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = [
            "-a", "-d", "cwd", "-F", "n",
            "-p", pids.map(String.init).joined(separator: ",")
        ]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            print("[ProcessDetector] lsof failed: \(error)")
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var cwds: Set<String> = []
        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("n") {
                let path = String(line.dropFirst())
                if !path.isEmpty {
                    cwds.insert(path)
                }
            }
        }
        return cwds
    }

    private static func normalize(_ path: String) -> String {
        var p = path
        while p.count > 1 && p.hasSuffix("/") {
            p = String(p.dropLast())
        }
        return p
    }
}
