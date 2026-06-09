import Foundation
import AppKit

final class DiagnosticsExporter {
    static let shared = DiagnosticsExporter()

    private let repoAPI = "https://api.github.com/repos/koersliven/Session-cove/issues"
    private let issuesURL = "https://github.com/koersliven/Session-cove/issues"

    enum Result {
        case issueCreated(url: String)
        case savedLocally(path: String)
        case error(String)
    }

    func export(userDescription: String = "") async -> Result {
        let body = buildReport(userDescription: userDescription)

        if let token = githubToken {
            do {
                let url = try await createGitHubIssue(body: body, token: token)
                return .issueCreated(url: url)
            } catch {
                DiagnosticLogger.shared.log("Issue creation failed: \(error)", module: "Diagnostics")
                return saveLocally(body: body)
            }
        } else {
            return saveLocally(body: body)
        }
    }

    // MARK: - Report Builder

    private func buildReport(userDescription: String) -> String {
        var parts: [String] = []

        if !userDescription.isEmpty {
            parts.append("## 问题描述\n\n\(userDescription)")
        }

        parts.append("## 系统信息\n\n```\n\(metadata())\n```")
        parts.append("## 最近日志\n\n```\n\(recentLogs())\n```")
        parts.append("## Hook 配置\n\n```json\n\(hookConfig())\n```")
        parts.append("## Workspace 配置\n\n```json\n\(workspaceConfig())\n```")

        let hookDebug = hookDebugLog()
        if !hookDebug.isEmpty {
            parts.append("## Hook Debug Log\n\n```\n\(hookDebug)\n```")
        }

        return parts.joined(separator: "\n\n---\n\n")
    }

    private func metadata() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let macOS = ProcessInfo.processInfo.operatingSystemVersionString
        let locale = Locale.current.identifier
        let now = ISO8601DateFormatter().string(from: Date())
        return """
        App Version: \(version) (\(build))
        macOS: \(macOS)
        Locale: \(locale)
        Timestamp: \(now)
        """
    }

    private func recentLogs() -> String {
        let logs = DiagnosticLogger.shared.recentLines(count: 300)
        return logs.isEmpty ? "(no logs yet)" : logs
    }

    private func hookConfig() -> String {
        let settingsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: settingsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "(not found)"
        }
        // Only include hooks section
        if let hooks = json["hooks"] {
            let hooksData = try? JSONSerialization.data(withJSONObject: hooks, options: [.prettyPrinted, .sortedKeys])
            return hooksData.flatMap { String(data: $0, encoding: .utf8) } ?? "(parse error)"
        }
        return "(no hooks section)"
    }

    private func workspaceConfig() -> String {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".session-cove/workspaces.json")
        guard let content = try? String(contentsOf: path, encoding: .utf8) else {
            return "(not found)"
        }
        return String(content.prefix(2000))
    }

    private func hookDebugLog() -> String {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".session-cove/hooks/debug.log")
        guard let content = try? String(contentsOf: path, encoding: .utf8) else { return "" }
        let lines = content.components(separatedBy: .newlines)
        return lines.suffix(100).joined(separator: "\n")
    }

    // MARK: - GitHub Issue

    private func createGitHubIssue(body: String, token: String) async throws -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let title = "[Diagnostic] v\(version) - \(timestamp)"

        guard let url = URL(string: repoAPI) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "title": title,
            "body": body,
            "labels": ["diagnostic"]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }

        if http.statusCode == 201 || http.statusCode == 200 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let htmlURL = json["html_url"] as? String {
                return htmlURL
            }
        }

        // Label might not exist, retry without labels
        if http.statusCode == 422 {
            let payloadNoLabel: [String: Any] = ["title": title, "body": body]
            request.httpBody = try JSONSerialization.data(withJSONObject: payloadNoLabel)
            let (data2, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data2) as? [String: Any],
               let htmlURL = json["html_url"] as? String {
                return htmlURL
            }
        }

        throw URLError(.badServerResponse)
    }

    // MARK: - Local Fallback

    private func saveLocally(body: String) -> Result {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".session-cove/diagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let filename = "diagnostic-\(ISO8601DateFormatter().string(from: Date())).md"
            .replacingOccurrences(of: ":", with: "-")
        let filePath = dir.appendingPathComponent(filename)
        try? body.write(to: filePath, atomically: true, encoding: .utf8)

        NSWorkspace.shared.open(URL(string: issuesURL)!)
        return .savedLocally(path: filePath.path)
    }

    // MARK: - Token

    private var githubToken: String? {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".session-cove/github-token")
        guard let content = try? String(contentsOf: path, encoding: .utf8) else { return nil }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
