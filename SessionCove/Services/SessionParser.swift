import Foundation

enum SessionParser {
    private static var cache: [String: (modDate: Date, record: SessionRecord)] = [:]

    static func parse(filePath: String, projectDirEncoded: String) -> SessionRecord? {
        let url = URL(fileURLWithPath: filePath)
        let fileManager = FileManager.default

        guard let attrs = try? fileManager.attributesOfItem(atPath: filePath),
              let modDate = attrs[.modificationDate] as? Date else {
            return nil
        }

        if let cached = cache[filePath], cached.modDate == modDate {
            return cached.record
        }

        guard let handle = FileHandle(forReadingAtPath: filePath) else { return nil }
        defer { handle.closeFile() }

        let headerData = handle.readData(ofLength: 32768)
        guard !headerData.isEmpty else { return nil }

        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }
        let headerLines = headerString.components(separatedBy: "\n").filter { !$0.isEmpty }

        var sessionId: String = url.deletingPathExtension().lastPathComponent
        var cwd: String?
        var timestamp: Date?
        var firstMessage: String?
        var version: String?
        var gitBranch: String?

        let isoFormatter = ISO8601DateFormatter()

        for line in headerLines.prefix(10) {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            let type = json["type"] as? String

            if type == "permission-mode" {
                if let sid = json["sessionId"] as? String {
                    sessionId = sid
                }
            } else if type == "user" {
                cwd = json["cwd"] as? String
                version = json["version"] as? String
                gitBranch = json["gitBranch"] as? String

                if let ts = json["timestamp"] as? String {
                    timestamp = isoFormatter.date(from: ts)
                }

                if let message = json["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    firstMessage = content
                } else if let message = json["message"] as? [String: Any],
                          let content = message["content"] as? [[String: Any]] {
                    firstMessage = content
                        .first(where: { ($0["type"] as? String) == "text" })?["text"] as? String
                }

                break
            }
        }

        let aiTitle = extractSummary(handle: handle)

        let projectPath = cwd ?? decodeProjectPath(projectDirEncoded)

        let record = SessionRecord(
            id: sessionId,
            projectDirEncoded: projectDirEncoded,
            projectPath: projectPath,
            firstUserMessage: firstMessage,
            aiTitle: aiTitle,
            timestamp: timestamp,
            lastModified: modDate,
            version: version,
            gitBranch: gitBranch,
            status: .archived
        )

        cache[filePath] = (modDate, record)
        return record
    }

    private static func extractSummary(handle: FileHandle) -> String? {
        let fileSize = handle.seekToEndOfFile()
        let tailSize: UInt64 = 16384
        let seekPos = fileSize > tailSize ? fileSize - tailSize : 0

        handle.seek(toFileOffset: seekPos)
        let tailData = handle.readDataToEndOfFile()

        guard let tailString = String(data: tailData, encoding: .utf8) else { return nil }
        let lines = tailString.components(separatedBy: "\n")

        var awaySummary: String?
        var aiTitle: String?

        for line in lines.reversed() {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            let type = json["type"] as? String
            let subtype = json["subtype"] as? String

            if type == "system" && subtype == "away_summary" && awaySummary == nil {
                if let content = json["content"] as? String {
                    let cleaned = content
                        .replacingOccurrences(of: " (disable recaps in /config)", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    awaySummary = cleaned
                }
            }

            if type == "ai-title" && aiTitle == nil {
                aiTitle = json["aiTitle"] as? String
            }

            if awaySummary != nil { break }
        }

        return awaySummary ?? aiTitle
    }

    private static func decodeProjectPath(_ encoded: String) -> String {
        var path = encoded
        if path.hasPrefix("-") {
            path = "/" + String(path.dropFirst())
        }
        path = path.replacingOccurrences(of: "-", with: "/")
        return path
    }
}
