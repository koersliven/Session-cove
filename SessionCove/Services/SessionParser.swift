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
        if providerId == "codex" {
            return parseCodex(
                filePath: filePath,
                projectDirEncoded: projectDirEncoded
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

    /// Parse an OpenAI Codex rollout transcript.
    ///
    /// Codex JSONL is a stream of typed records. The metadata we need lives
    /// in two places:
    ///   * the first `session_meta` line carries `payload.id` (session id),
    ///     `payload.cwd` (project path), `payload.timestamp`, and
    ///     `payload.git.branch`.
    ///   * `event_msg` lines with `payload.type == "user_message"` /
    ///     `"agent_message"` carry a plain-string `payload.message`; we take
    ///     the first user message as the title seed and the last agent
    ///     message (from the tail) as the summary.
    ///
    /// `projectDirEncoded` is the date-partition path segment
    /// (e.g. `2026/07/08`) for the flat layout — it is not a project encoding,
    /// so the real project path always comes from `session_meta.cwd`.
    static func parseCodex(
        filePath: String,
        projectDirEncoded: String
    ) -> SessionRecord? {
        let url = URL(fileURLWithPath: filePath)
        let fileManager = FileManager.default

        guard let attrs = try? fileManager.attributesOfItem(atPath: filePath),
              let modDate = attrs[.modificationDate] as? Date else {
            return nil
        }

        let cacheKey = "codex|\(filePath)"
        if let cached = cache[cacheKey], cached.modDate == modDate {
            return cached.record
        }

        guard let handle = FileHandle(forReadingAtPath: filePath) else { return nil }
        defer { handle.closeFile() }

        // Session id falls back to the uuid embedded in the filename
        // (`rollout-<ts>-<uuid>.jsonl`) if the header can't be read.
        var sessionId = codexSessionIdFromFilename(url.deletingPathExtension().lastPathComponent)
        var cwd: String?
        var timestamp: Date?
        var gitBranch: String?
        var version: String?
        var firstUserMessage: String?

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Header pass: read enough of the file to catch the session_meta line
        // and the first user_message.
        let headerData = handle.readData(ofLength: 65536)
        if let headerString = String(data: headerData, encoding: .utf8) {
            for line in headerString.components(separatedBy: "\n") where !line.isEmpty {
                guard let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue
                }
                let type = json["type"] as? String
                let payload = json["payload"] as? [String: Any]

                if type == "session_meta", let payload = payload {
                    if let sid = payload["id"] as? String { sessionId = sid }
                    cwd = payload["cwd"] as? String
                    version = payload["cli_version"] as? String
                    if let git = payload["git"] as? [String: Any] {
                        gitBranch = git["branch"] as? String
                    }
                    if let ts = payload["timestamp"] as? String {
                        timestamp = isoFormatter.date(from: ts) ?? ISO8601DateFormatter().date(from: ts)
                    }
                } else if type == "event_msg",
                          let payload = payload,
                          payload["type"] as? String == "user_message",
                          firstUserMessage == nil,
                          let message = payload["message"] as? String,
                          !message.isEmpty {
                    firstUserMessage = message
                }

                if cwd != nil && firstUserMessage != nil { break }
            }
        }

        let aiTitle = extractCodexTailSummary(handle: handle)

        let projectPath = cwd ?? decodeProjectPath(projectDirEncoded)

        let record = SessionRecord(
            id: sessionId,
            providerId: "codex",
            projectDirEncoded: projectDirEncoded,
            projectPath: projectPath,
            jsonlPath: filePath,
            firstUserMessage: firstUserMessage,
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

    /// Extract the uuid from a Codex rollout filename
    /// `rollout-2026-07-08T14-24-40-<uuid>`. Returns the whole basename when
    /// the pattern doesn't match so we always have a stable id.
    private static func codexSessionIdFromFilename(_ base: String) -> String {
        // uuid is the last 5 dash-joined groups (8-4-4-4-12).
        let parts = base.components(separatedBy: "-")
        guard parts.count >= 5 else { return base }
        let uuidParts = parts.suffix(5)
        let candidate = uuidParts.joined(separator: "-")
        // Cheap sanity check: a v4/v7 uuid is 36 chars.
        return candidate.count == 36 ? candidate : base
    }

    /// Scan the last 32KB of a Codex transcript for the final
    /// `agent_message` and return its first ~120 chars as a summary. Codex
    /// writes no ai-title/away_summary header, so the latest agent turn is
    /// the best available one-line description.
    private static func extractCodexTailSummary(handle: FileHandle) -> String? {
        let fileSize = handle.seekToEndOfFile()
        let tailSize: UInt64 = 32768
        let seekPos = fileSize > tailSize ? fileSize - tailSize : 0
        handle.seek(toFileOffset: seekPos)
        let tailData = handle.readDataToEndOfFile()

        guard let tailString = String(data: tailData, encoding: .utf8) else { return nil }
        let lines = tailString.components(separatedBy: "\n")

        for line in lines.reversed() {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["type"] as? String == "event_msg",
                  let payload = json["payload"] as? [String: Any],
                  payload["type"] as? String == "agent_message",
                  let message = payload["message"] as? String,
                  message.count > 20 else {
                continue
            }
            let cleaned = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return String(cleaned.prefix(120))
        }
        return nil
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

    /// Scan the last 16KB of a Qoder transcript for the final assistant text
    /// message and return its first ~120 chars as a summary.
    private static func extractQoderTailSummary(handle: FileHandle) -> String? {
        let fileSize = handle.seekToEndOfFile()
        let tailSize: UInt64 = 16384
        let seekPos = fileSize > tailSize ? fileSize - tailSize : 0
        handle.seek(toFileOffset: seekPos)
        let tailData = handle.readDataToEndOfFile()

        guard let tailString = String(data: tailData, encoding: .utf8) else { return nil }
        let lines = tailString.components(separatedBy: "\n")

        // Walk backwards to find the last assistant line with text content
        for line in lines.reversed() {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["type"] as? String == "assistant",
                  let message = json["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]] else {
                continue
            }
            for block in content {
                if block["type"] as? String == "text",
                   let text = block["text"] as? String,
                   text.count > 40 {
                    return String(text.prefix(120))
                }
            }
        }
        return nil
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

    /// Qoder/QoderWork transcript schema (actual, as of qodercli 2026):
    ///
    ///   {type:"assistant"|"user"|"progress",
    ///    sessionId:"...", uuid:"...", timestamp:"2026-...Z", cwd:"/path",
    ///    message:{role:"assistant"|"user",
    ///             content:[{type:"text", text:"..."}|{type:"tool_use",...}]}}
    ///
    /// Every line carries `sessionId`, `cwd`, and `timestamp` at the top
    /// level.  No `permission-mode` header, `ai-title`, `version`, or
    /// `gitBranch` is written.  Token usage is also absent.
    ///
    /// We extract `sessionId` / `cwd` / `timestamp` from the first line that
    /// has them, and `firstUserMessage` from the first `type:"user"` line.
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

        // Fallback: filename-derived sessionId.
        var sessionId = url.deletingPathExtension().lastPathComponent
        if sessionId.hasSuffix("-session") {
            sessionId = String(sessionId.dropLast("-session".count))
        }

        var cwd: String?
        var timestamp: Date?
        var firstUserMessage: String?

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFormatterNoFraction = ISO8601DateFormatter()

        for line in headerLines.prefix(40) {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            let type = json["type"] as? String

            // Grab metadata from the first line that carries sessionId / cwd
            if sessionId == url.deletingPathExtension().lastPathComponent,
               let sid = json["sessionId"] as? String, !sid.isEmpty {
                sessionId = sid
            }
            if cwd == nil, let c = json["cwd"] as? String, !c.isEmpty {
                cwd = c
            }
            if timestamp == nil, let ts = json["timestamp"] as? String {
                timestamp = isoFormatter.date(from: ts)
                    ?? isoFormatterNoFraction.date(from: ts)
            }

            // Extract first user text
            if type == "user", firstUserMessage == nil,
               let message = json["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                firstUserMessage = content
                    .first(where: { ($0["type"] as? String) == "text" })?["text"] as? String
            }

            // Stop early once we have all fields
            if cwd != nil, timestamp != nil, firstUserMessage != nil, sessionId != url.deletingPathExtension().lastPathComponent {
                break
            }
        }

        // Attempt to extract a summary from the tail of the transcript.
        // Qoder doesn't write ai-title / away_summary headers, so we take
        // the text content of the last assistant message (if substantial).
        let aiTitle = extractQoderTailSummary(handle: handle)

        let projectPath = cwd ?? decodeProjectPath(projectDirEncoded)

        let record = SessionRecord(
            id: sessionId,
            providerId: providerId,
            projectDirEncoded: projectDirEncoded,
            projectPath: projectPath,
            jsonlPath: filePath,
            firstUserMessage: firstUserMessage,
            aiTitle: aiTitle,
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
