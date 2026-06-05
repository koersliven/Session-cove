import Foundation

enum SessionParser {
    private static var cache: [String: (modDate: Date, record: SessionRecord)] = [:]

    /// Backward-compatible entry point used before multi-provider support.
    /// Defaults to the "claude" provider so existing tests / call sites keep
    /// working unchanged.
    static func parse(filePath: String, projectDirEncoded: String) -> SessionRecord? {
        parse(filePath: filePath, projectDirEncoded: projectDirEncoded, providerId: "claude")
    }

    /// Multi-provider entry point. Dispatches by `providerId`:
    ///
    ///   * `"cursor"` → `CursorTranscriptParser.parse(...)` (role/content
    ///     parts shape, no permission-mode header, no ai-title).
    ///   * `"qoder"` / `"qoderwork"` → `parseQoder(...)` — Qoder writes a
    ///     `session_meta` header line carrying sessionId/cwd/timestamp,
    ///     followed by `progress`/`user`/`assistant` lines whose `data`
    ///     is null for user/assistant. We extract the metadata line and
    ///     fall back to filename-derived sessionId if absent.
    ///   * `"claude"` → the original decoder below (`permission-mode` +
    ///     `user` + `ai-title` lines).
    static func parse(
        filePath: String,
        projectDirEncoded: String,
        providerId: String
    ) -> SessionRecord? {
        if providerId == "cursor" {
            return CursorTranscriptParser.parse(
                filePath: filePath,
                projectDirEncoded: projectDirEncoded
            )
        }
        if providerId == "qoder" || providerId == "qoderwork" {
            return parseQoder(
                filePath: filePath,
                projectDirEncoded: projectDirEncoded,
                providerId: providerId
            )
        }
        let url = URL(fileURLWithPath: filePath)
        let fileManager = FileManager.default

        guard let attrs = try? fileManager.attributesOfItem(atPath: filePath),
              let modDate = attrs[.modificationDate] as? Date else {
            return nil
        }

        let cacheKey = "\(providerId)|\(filePath)"
        if let cached = cache[cacheKey], cached.modDate == modDate {
            return cached.record
        }

        guard let handle = FileHandle(forReadingAtPath: filePath) else { return nil }
        defer { handle.closeFile() }

        let headerData = handle.readData(ofLength: 8192)
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

        var headerAiTitle: String?

        for line in headerLines.prefix(40) {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            let type = json["type"] as? String

            if type == "permission-mode" {
                if let sid = json["sessionId"] as? String {
                    sessionId = sid
                }
            } else if type == "user" && firstMessage == nil {
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
            } else if type == "ai-title" {
                if let title = json["aiTitle"] as? String, !title.isEmpty {
                    headerAiTitle = title
                    break
                }
            }
        }

        let aiTitle = headerAiTitle ?? extractSummary(handle: handle)

        let projectPath = cwd ?? decodeProjectPath(projectDirEncoded)

        let record = SessionRecord(
            id: sessionId,
            providerId: providerId,
            projectDirEncoded: projectDirEncoded,
            projectPath: projectPath,
            jsonlPath: filePath,
            firstUserMessage: firstMessage,
            aiTitle: aiTitle,
            timestamp: timestamp,
            lastModified: modDate,
            version: version,
            gitBranch: gitBranch,
            status: .archived
        )

        cache[cacheKey] = (modDate, record)
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

    // MARK: - Qoder dialect

    /// Qoder/QoderWork transcript schema:
    ///   line 0: {type:"session_meta", sessionId, uuid, timestamp, cwd, data:{...}}
    ///   line N: {type:"progress", data:{command, hookEvent, hookName, type}}
    ///   line N: {type:"user"|"assistant", data:null}
    ///
    /// User/assistant content lives in subsequent encoded fields we don't
    /// have a fixed shape for yet; for v1 we grab metadata from session_meta
    /// and the first non-null user/assistant line for `firstMessage` if
    /// possible. lastModified comes from the file's mtime.
    private static func parseQoder(
        filePath: String,
        projectDirEncoded: String,
        providerId: String
    ) -> SessionRecord? {
        let url = URL(fileURLWithPath: filePath)
        let fileManager = FileManager.default

        guard let attrs = try? fileManager.attributesOfItem(atPath: filePath),
              let modDate = attrs[.modificationDate] as? Date else {
            return nil
        }

        let cacheKey = "\(providerId)|\(filePath)"
        if let cached = cache[cacheKey], cached.modDate == modDate {
            return cached.record
        }

        guard let handle = FileHandle(forReadingAtPath: filePath) else { return nil }
        defer { handle.closeFile() }

        let headerData = handle.readData(ofLength: 8192)
        guard !headerData.isEmpty,
              let headerString = String(data: headerData, encoding: .utf8) else {
            return nil
        }
        let headerLines = headerString.components(separatedBy: "\n").filter { !$0.isEmpty }

        // Default to filename-derived sessionId so a malformed session_meta
        // line still produces a usable record.
        var sessionId = url.deletingPathExtension().lastPathComponent
        // Qoder filenames sometimes include a "-session" suffix (companion
        // sidecar files we don't want to confuse with the real transcript)
        // — the SessionScanner already filters by .jsonl extension; here we
        // just trim the suffix if it slipped through.
        if sessionId.hasSuffix("-session") {
            sessionId = String(sessionId.dropLast("-session".count))
        }

        var cwd: String?
        var timestamp: Date?
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFormatterNoFraction = ISO8601DateFormatter()

        for line in headerLines.prefix(20) {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            if json["type"] as? String == "session_meta" {
                if let sid = json["sessionId"] as? String, !sid.isEmpty {
                    sessionId = sid
                }
                if let c = json["cwd"] as? String, !c.isEmpty {
                    cwd = c
                }
                if let ts = json["timestamp"] as? String {
                    timestamp = isoFormatter.date(from: ts) ?? isoFormatterNoFraction.date(from: ts)
                }
                break
            }
        }

        let projectPath = cwd ?? decodeProjectPath(projectDirEncoded)

        let record = SessionRecord(
            id: sessionId,
            providerId: providerId,
            projectDirEncoded: projectDirEncoded,
            projectPath: projectPath,
            jsonlPath: filePath,
            firstUserMessage: nil,
            aiTitle: nil,
            timestamp: timestamp,
            lastModified: modDate,
            version: nil,
            gitBranch: nil,
            status: .archived
        )
        cache[cacheKey] = (modDate, record)
        return record
    }
}
