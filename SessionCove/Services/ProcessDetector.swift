import Foundation

final class ProcessDetector: @unchecked Sendable {
    static let shared = ProcessDetector()

    func detectActiveSessionIds(candidateIds: Set<String> = []) -> Set<String> {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-eo", "pid,args"]
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

        var activeIds: Set<String> = []

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.contains("claude") else { continue }

            if let range = trimmed.range(of: "--resume ") {
                let afterResume = trimmed[range.upperBound...]
                let sessionId = afterResume.prefix(while: { !$0.isWhitespace })
                if !sessionId.isEmpty {
                    activeIds.insert(String(sessionId))
                }
            }

            for id in candidateIds where trimmed.contains(id) {
                activeIds.insert(id)
            }
        }

        return activeIds
    }

    func applyStatuses(activeIds: Set<String>, to islands: inout [ProjectIsland]) {
        let now = Date()
        let recentThreshold: TimeInterval = 24 * 60 * 60

        for i in islands.indices {
            for j in islands[i].sessions.indices {
                let session = islands[i].sessions[j]
                if activeIds.contains(session.id) {
                    islands[i].sessions[j].status = .active
                } else if now.timeIntervalSince(session.lastModified) < recentThreshold {
                    islands[i].sessions[j].status = .recentlyIdle
                } else {
                    islands[i].sessions[j].status = .archived
                }
            }
        }
    }
}
