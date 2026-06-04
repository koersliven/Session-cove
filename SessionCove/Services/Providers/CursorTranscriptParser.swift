import Foundation

/// Parser for Cursor Agent transcript JSONL files.
///
/// Cursor's transcript shape diverges from Claude's: each line is an
/// object with `role` (`"user"` | `"assistant"`) and `content` — an
/// array of typed parts (`text`, `tool_use`, `tool_result`). There is
/// no `permission-mode` line and no `ai-title` line.
///
/// ```jsonl
/// {"role":"user","content":[{"type":"text","text":"refactor foo.ts"}]}
/// {"role":"assistant","content":[{"type":"text","text":"Sure, here's the plan…"}]}
/// {"role":"assistant","content":[{"type":"tool_use","name":"edit","input":{...}}]}
/// {"role":"user","content":[{"type":"tool_result","tool_use_id":"…","content":"ok"}]}
/// ```
///
/// This parser maps that shape onto Session Cove's existing
/// `SessionRecord`:
///
///   * `firstUserMessage` ← first `user.content[type=text].text`
///   * `aiTitle` ← `nil` for now (Cursor does not emit a title; later
///     steps may synthesize one from the first assistant text or pull
///     it from a sidecar file)
///   * `timestamp` ← file mtime (Cursor lines do not carry an ISO ts)
///   * `lastModified` ← file mtime
///   * `id` ← filename without extension
///   * `providerId` ← `"cursor"`
///   * `cwd` / `version` / `gitBranch` ← `nil` (not in Cursor lines)
///
/// Step 9 only adds this parser; `SessionParser.parse(...)` is **not**
/// changed yet. Step 10 will wire `SessionParser` to dispatch by
/// `providerId`. Until then this code is unreachable, so it cannot
/// affect the live Claude path.
enum CursorTranscriptParser {
    /// Parse a Cursor JSONL transcript at `filePath`. Returns `nil` for
    /// missing/unreadable files or when no usable header data is found.
    ///
    /// - Parameters:
    ///   - filePath: Absolute path to the JSONL file (e.g.
    ///     `~/.cursor/projects/<encoded>/<id>.jsonl`).
    ///   - projectDirEncoded: Encoded project directory name (the
    ///     parent folder under `~/.cursor/projects`). Mirrors the
    ///     Claude parser's parameter.
    static func parse(
        filePath: String,
        projectDirEncoded: String
    ) -> SessionRecord? {
        let url = URL(fileURLWithPath: filePath)
        let fileManager = FileManager.default

        guard let attrs = try? fileManager.attributesOfItem(atPath: filePath),
              let modDate = attrs[.modificationDate] as? Date else {
            return nil
        }

        let sessionId = url.deletingPathExtension().lastPathComponent

        guard let handle = FileHandle(forReadingAtPath: filePath) else { return nil }
        defer { handle.closeFile() }

        let headerData = handle.readData(ofLength: 8192)
        guard !headerData.isEmpty else { return nil }
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }

        let headerLines = headerString
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }

        var firstUserMessage: String?

        for line in headerLines.prefix(40) {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            let role = json["role"] as? String

            // Only the first user line with a text part counts.
            if role == "user", firstUserMessage == nil {
                firstUserMessage = extractText(from: json["content"])
                if firstUserMessage != nil { break }
            }
        }

        let projectPath = decodeProjectPath(projectDirEncoded)

        return SessionRecord(
            id: sessionId,
            providerId: "cursor",
            projectDirEncoded: projectDirEncoded,
            projectPath: projectPath,
            jsonlPath: filePath,
            firstUserMessage: firstUserMessage,
            aiTitle: nil,
            timestamp: modDate,
            lastModified: modDate,
            version: nil,
            gitBranch: nil,
            status: .archived
        )
    }

    /// Pull the first `text` part out of a Cursor `content` array. Returns
    /// `nil` if the value isn't an array of dicts or no text part is
    /// present.
    private static func extractText(from content: Any?) -> String? {
        // Cursor encodes content as an array of typed parts.
        if let parts = content as? [[String: Any]] {
            for part in parts {
                if (part["type"] as? String) == "text",
                   let text = part["text"] as? String,
                   !text.isEmpty {
                    return text
                }
            }
            return nil
        }
        // Defensive: if some line uses a plain-string content (older
        // Cursor versions sometimes do), accept it as-is.
        if let text = content as? String, !text.isEmpty {
            return text
        }
        return nil
    }

    /// Same encoding scheme as Claude / Qoder: leading "-" → "/", and
    /// remaining "-" → "/". Cursor uses the same pattern under
    /// `~/.cursor/projects/`.
    private static func decodeProjectPath(_ encoded: String) -> String {
        var path = encoded
        if path.hasPrefix("-") {
            path = "/" + String(path.dropFirst())
        }
        path = path.replacingOccurrences(of: "-", with: "/")
        return path
    }
}
