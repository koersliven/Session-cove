import Foundation

enum DailyReportCollector {
    @MainActor
    static func collect(hours: Int = 24) -> [ReportSessionData] {
        let islands = SessionScanner.scan()
        let cutoff = Date().addingTimeInterval(-Double(hours) * 3600)

        var projectDataMap: [String: ReportSessionData] = [:]

        for island in islands {
            let recentSessions = island.sessions.filter { $0.lastModified > cutoff }
            guard !recentSessions.isEmpty else { continue }

            var entries: [ReportSessionEntry] = []
            for session in recentSessions {
                let result = deepExtract(from: session.jsonlPath)
                entries.append(ReportSessionEntry(
                    sessionId: session.id,
                    aiTitle: session.aiTitle,
                    firstUserMessage: result.userMessages.first ?? session.firstUserMessage,
                    gitBranch: session.gitBranch,
                    timestamp: session.timestamp,
                    lastModified: session.lastModified,
                    userMessages: result.userMessages,
                    assistantOutcomes: result.outcomes,
                    messageCount: result.totalMessages,
                    tokenStats: result.tokenStats
                ))
            }

            let key = island.path
            if var existing = projectDataMap[key] {
                existing = ReportSessionData(
                    projectName: existing.projectName,
                    path: existing.path,
                    sessions: existing.sessions + entries
                )
                projectDataMap[key] = existing
            } else {
                projectDataMap[key] = ReportSessionData(
                    projectName: island.displayName,
                    path: island.path,
                    sessions: entries
                )
            }
        }

        return Array(projectDataMap.values).sorted {
            let lhs = $0.sessions.map(\.lastModified).max() ?? .distantPast
            let rhs = $1.sessions.map(\.lastModified).max() ?? .distantPast
            return lhs > rhs
        }
    }

    private struct DeepExtractResult {
        var userMessages: [String] = []
        var outcomes: [String] = []
        var totalMessages: Int = 0
        var tokenStats: DailyReport.TokenStats = DailyReport.TokenStats()
    }

    /// Deep extraction: read all user messages + key assistant outcomes + token stats.
    private static func deepExtract(from jsonlPath: String) -> DeepExtractResult {
        guard let handle = FileHandle(forReadingAtPath: jsonlPath) else {
            return DeepExtractResult()
        }
        defer { handle.closeFile() }

        let fileSize = handle.seekToEndOfFile()
        handle.seek(toFileOffset: 0)

        let chunkSize: UInt64 = 65536
        var buffer = ""
        var result = DeepExtractResult()
        var lastAssistantText: String?
        var seenUserTexts = Set<String>()
        let skipPatterns = [
            "Continue from where you left off",
            "<task-notification>",
            "<system-reminder>",
            "go on",
            "继续"
        ]

        var offset: UInt64 = 0
        while offset < fileSize {
            let remaining = fileSize - offset
            let readSize = min(chunkSize, remaining)
            handle.seek(toFileOffset: offset)
            guard let chunkData = try? handle.read(upToCount: Int(readSize)),
                  let chunk = String(data: chunkData, encoding: .utf8) else {
                break
            }
            buffer += chunk
            offset += readSize

            let lines = buffer.components(separatedBy: "\n")
            buffer = lines.last ?? ""
            for line in lines.dropLast() where !line.isEmpty {
                guard let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue
                }

                let type = json["type"] as? String
                result.totalMessages += 1

                // Token extraction from assistant messages
                if type == "assistant",
                   let message = json["message"] as? [String: Any],
                   let usage = message["usage"] as? [String: Any] {
                    let model = message["model"] as? String ?? ""
                    if model != "<synthetic>" {
                        result.tokenStats.apiCalls += 1
                        let input = (usage["input_tokens"] as? Int ?? 0)
                            + (usage["cache_creation_input_tokens"] as? Int ?? 0)
                            + (usage["cache_read_input_tokens"] as? Int ?? 0)
                        let output = usage["output_tokens"] as? Int ?? 0
                        result.tokenStats.totalInput += input
                        result.tokenStats.totalOutput += output
                        result.tokenStats.totalCacheRead += usage["cache_read_input_tokens"] as? Int ?? 0
                        result.tokenStats.totalCacheWrite += usage["cache_creation_input_tokens"] as? Int ?? 0
                    }
                }

                if type == "user" {
                    if let text = extractMessageText(from: json),
                       text.count > 5,
                       !skipPatterns.contains(where: { text.contains($0) }) {
                        let truncated = String(text.prefix(200))
                        if !seenUserTexts.contains(truncated) {
                            seenUserTexts.insert(truncated)
                            result.userMessages.append(truncated)
                        }
                    }
                    if let outcome = lastAssistantText {
                        result.outcomes.append(outcome)
                        lastAssistantText = nil
                    }
                } else if type == "assistant" {
                    if let text = extractMessageText(from: json), text.count > 80 {
                        lastAssistantText = String(text.prefix(300))
                    }
                }
            }
        }

        if let outcome = lastAssistantText {
            result.outcomes.append(outcome)
        }

        return result
    }

    private static func extractMessageText(from json: [String: Any]) -> String? {
        guard let message = json["message"] as? [String: Any] else { return nil }
        if let content = message["content"] as? String, !content.isEmpty {
            return content
        }
        if let content = message["content"] as? [[String: Any]] {
            return content
                .first(where: { ($0["type"] as? String) == "text" })?["text"] as? String
        }
        return nil
    }
}
