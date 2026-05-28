import Foundation

enum ClaudePermissionHook {
    private static let supportDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".session-cove", isDirectory: true)
    private static let hookDirectory = supportDirectory.appendingPathComponent("hooks", isDirectory: true)
    private static let pendingDirectory = hookDirectory.appendingPathComponent("pending", isDirectory: true)
    private static let responseDirectory = hookDirectory.appendingPathComponent("responses", isDirectory: true)
    private static let binDirectory = supportDirectory.appendingPathComponent("bin", isDirectory: true)
    private static let scriptURL = binDirectory.appendingPathComponent("session_cove_claude_hook.py")
    private static let managedMarker = "Session Cove managed PermissionRequest hook"

    static func install() throws {
        let fileManager = FileManager.default
        try [supportDirectory, hookDirectory, pendingDirectory, responseDirectory, binDirectory].forEach { url in
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }

        try bridgeScript.data(using: .utf8)?.write(to: scriptURL, options: .atomic)
        try updateClaudeSettings()
    }

    static func pendingRequests() -> [HookPermissionRequest] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: pendingDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let id = object["id"] as? String,
                      let toolName = object["toolName"] as? String,
                      let projectPath = object["projectPath"] as? String,
                      let summary = object["summary"] as? String else {
                    return nil
                }

                let receivedAt = (object["receivedAt"] as? TimeInterval).map(Date.init(timeIntervalSince1970:)) ?? Date()
                return HookPermissionRequest(
                    id: id,
                    toolName: toolName,
                    projectPath: projectPath,
                    summary: summary,
                    receivedAt: receivedAt
                )
            }
            .sorted { $0.receivedAt < $1.receivedAt }
    }

    static func resolve(request: HookPermissionRequest, decision: HookApprovalDecision) throws {
        try FileManager.default.createDirectory(at: responseDirectory, withIntermediateDirectories: true)
        let response: [String: Any] = [
            "id": request.id,
            "decision": decision.rawValue,
            "decidedAt": Date().timeIntervalSince1970
        ]
        let data = try JSONSerialization.data(withJSONObject: response, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: responseDirectory.appendingPathComponent("\(request.id).json"), options: .atomic)
        try? FileManager.default.removeItem(at: pendingDirectory.appendingPathComponent("\(request.id).json"))
    }

    private static func updateClaudeSettings() throws {
        let settingsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("settings.json")
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let existingData = try? Data(contentsOf: settingsURL)
        var root: [String: Any] = existingData.flatMap(HookConfigParser.parseJSONObject(from:)) ?? [:]
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let existingEntries = hooks["PermissionRequest"] as? [[String: Any]] ?? []
        let preservedEntries = existingEntries.filter { !containsSessionCoveCommand($0) }
        let newEntry: [String: Any] = [
            "hooks": [
                [
                    "type": "command",
                    "command": "/usr/bin/python3 \(shellQuoted(scriptURL.path))",
                    "timeout": 86400,
                    "statusMessage": "Session Cove is waiting for approval"
                ]
            ]
        ]

        hooks["PermissionRequest"] = preservedEntries + [newEntry]
        root["hooks"] = hooks

        if let existingData, !containsSessionCoveCommandInData(existingData) {
            let backupURL = settingsURL.deletingLastPathComponent()
                .appendingPathComponent("settings.session-cove-backup.json")
            if !FileManager.default.fileExists(atPath: backupURL.path) {
                try? existingData.write(to: backupURL, options: .atomic)
            }
        }

        var options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys]
        options.insert(.withoutEscapingSlashes)
        let data = try JSONSerialization.data(withJSONObject: root, options: options)
        try data.write(to: settingsURL, options: .atomic)
    }

    private static func containsSessionCoveCommandInData(_ data: Data) -> Bool {
        String(data: data, encoding: .utf8)?.contains("session_cove_claude_hook.py") == true
    }

    private static func containsSessionCoveCommand(_ entry: [String: Any]) -> Bool {
        if (entry["command"] as? String)?.contains("session_cove_claude_hook.py") == true {
            return true
        }

        if let nested = entry["hooks"] as? [[String: Any]] {
            return nested.contains { containsSessionCoveCommand($0) }
        }

        return false
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static var bridgeScript: String {
        """
        #!/usr/bin/env python3
        import hashlib
        import json
        import os
        import sys
        import time

        ROOT = os.path.expanduser("~/.session-cove/hooks")
        PENDING = os.path.join(ROOT, "pending")
        RESPONSES = os.path.join(ROOT, "responses")
        TIMEOUT_SECONDS = 24 * 60 * 60

        def ensure_dirs():
            os.makedirs(PENDING, exist_ok=True)
            os.makedirs(RESPONSES, exist_ok=True)

        def stable_summary(payload):
            tool_name = str(payload.get("tool_name") or "Tool")
            tool_input = payload.get("tool_input") or {}
            if isinstance(tool_input, dict):
                for key in ("command", "file_path", "path", "url", "description"):
                    value = tool_input.get(key)
                    if value:
                        return f"{tool_name}: {str(value)[:220]}"
                try:
                    return f"{tool_name}: {json.dumps(tool_input, ensure_ascii=False, sort_keys=True)[:220]}"
                except Exception:
                    pass
            return f"{tool_name} is asking for permission."

        def make_request_id(payload):
            seed = json.dumps(payload, ensure_ascii=False, sort_keys=True, default=str) + str(time.time())
            return hashlib.sha256(seed.encode("utf-8")).hexdigest()[:24]

        def build_fallback_permission(payload, value):
            tool_name = str(payload.get("tool_name") or "Tool")
            tool_input = payload.get("tool_input") or {}
            destination = "session" if value == "allowSession" else "localSettings"
            if tool_name == "Bash":
                command = tool_input.get("command", "") if isinstance(tool_input, dict) else ""
                if command:
                    binary = command.strip().split()[0] if command.strip() else ""
                    if binary in ("git", "ls", "cat", "grep", "find", "npm", "yarn", "swift", "python3", "python"):
                        rule_content = f"allow tool: Bash matching command starting with '{binary}'"
                    else:
                        rule_content = f"allow tool: Bash matching command: {command[:120]}"
                else:
                    rule_content = "allow tool: Bash"
            elif tool_name in ("Read", "Write", "Edit"):
                path = ""
                if isinstance(tool_input, dict):
                    path = tool_input.get("file_path") or tool_input.get("path") or ""
                if path:
                    rule_content = f"allow tool: {tool_name} matching file_path: {path}"
                else:
                    rule_content = f"allow tool: {tool_name}"
            else:
                rule_content = f"allow tool: {tool_name}"
            return [{"toolName": tool_name, "ruleContent": rule_content, "destination": destination}]

        def output_decision(payload, decision):
            value = decision.get("decision")
            hook_output = {
                "hookEventName": "PermissionRequest",
                "decision": {}
            }
            if value == "deny":
                hook_output["decision"] = {
                    "behavior": "deny",
                    "message": "Denied in Session Cove.",
                    "interrupt": True
                }
            else:
                hook_output["decision"] = {"behavior": "allow"}
                if value in ("allowSession", "alwaysAllow"):
                    suggestions = payload.get("permission_suggestions")
                    if isinstance(suggestions, list) and suggestions:
                        updates = []
                        for suggestion in suggestions:
                            if isinstance(suggestion, dict):
                                cloned = dict(suggestion)
                                if value == "allowSession":
                                    cloned["destination"] = "session"
                                elif value == "alwaysAllow":
                                    cloned["destination"] = "localSettings"
                                updates.append(cloned)
                        if updates:
                            hook_output["decision"]["updatedPermissions"] = updates
                    else:
                        hook_output["decision"]["updatedPermissions"] = build_fallback_permission(payload, value)
            print(json.dumps({"hookSpecificOutput": hook_output}, ensure_ascii=False), flush=True)

        def main():
            ensure_dirs()
            raw = sys.stdin.read()
            if not raw.strip():
                return 0
            try:
                payload = json.loads(raw)
            except Exception:
                return 0

            if payload.get("hook_event_name") != "PermissionRequest":
                return 0

            request_id = make_request_id(payload)
            request_path = os.path.join(PENDING, f"{request_id}.json")
            response_path = os.path.join(RESPONSES, f"{request_id}.json")
            request = {
                "id": request_id,
                "toolName": str(payload.get("tool_name") or "Tool"),
                "projectPath": str(payload.get("cwd") or os.getcwd()),
                "summary": stable_summary(payload),
                "receivedAt": time.time(),
                "rawPayload": payload
            }
            temp_path = request_path + ".tmp"
            with open(temp_path, "w", encoding="utf-8") as handle:
                json.dump(request, handle, ensure_ascii=False, indent=2, sort_keys=True)
            os.replace(temp_path, request_path)

            deadline = time.time() + TIMEOUT_SECONDS
            while time.time() < deadline:
                if os.path.exists(response_path):
                    with open(response_path, "r", encoding="utf-8") as handle:
                        decision = json.load(handle)
                    output_decision(payload, decision)
                    try:
                        os.remove(request_path)
                    except OSError:
                        pass
                    return 0
                time.sleep(0.2)
            return 0

        if __name__ == "__main__":
            raise SystemExit(main())
        """
    }
}

private enum HookConfigParser {
    static func parseJSONObject(from data: Data) -> [String: Any]? {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return json
        }

        guard let string = String(data: data, encoding: .utf8),
              let sanitizedData = removeTrailingCommas(from: stripJSONComments(from: string)).data(using: .utf8) else {
            return nil
        }

        return try? JSONSerialization.jsonObject(with: sanitizedData) as? [String: Any]
    }

    private static func stripJSONComments(from string: String) -> String {
        var output = ""
        var index = string.startIndex
        var isInsideString = false
        var isEscaping = false
        var isLineComment = false
        var isBlockComment = false

        while index < string.endIndex {
            let character = string[index]
            let nextIndex = string.index(after: index)
            let nextCharacter = nextIndex < string.endIndex ? string[nextIndex] : nil

            if isLineComment {
                if character == "\n" {
                    isLineComment = false
                    output.append(character)
                }
                index = nextIndex
                continue
            }

            if isBlockComment {
                if character == "\n" {
                    output.append(character)
                } else if character == "*", nextCharacter == "/" {
                    isBlockComment = false
                    index = string.index(after: nextIndex)
                    continue
                }
                index = nextIndex
                continue
            }

            if isInsideString {
                output.append(character)
                if isEscaping {
                    isEscaping = false
                } else if character == "\\" {
                    isEscaping = true
                } else if character == "\"" {
                    isInsideString = false
                }
                index = nextIndex
                continue
            }

            if character == "\"" {
                isInsideString = true
                output.append(character)
                index = nextIndex
                continue
            }

            if character == "/", nextCharacter == "/" {
                isLineComment = true
                index = string.index(after: nextIndex)
                continue
            }

            if character == "/", nextCharacter == "*" {
                isBlockComment = true
                index = string.index(after: nextIndex)
                continue
            }

            output.append(character)
            index = nextIndex
        }

        return output
    }

    private static func removeTrailingCommas(from string: String) -> String {
        let characters = Array(string)
        var output = ""
        var index = 0
        var isInsideString = false
        var isEscaping = false

        while index < characters.count {
            let character = characters[index]

            if isInsideString {
                output.append(character)
                if isEscaping {
                    isEscaping = false
                } else if character == "\\" {
                    isEscaping = true
                } else if character == "\"" {
                    isInsideString = false
                }
                index += 1
                continue
            }

            if character == "\"" {
                isInsideString = true
                output.append(character)
                index += 1
                continue
            }

            if character == "," {
                var lookahead = index + 1
                while lookahead < characters.count, characters[lookahead].isWhitespace {
                    lookahead += 1
                }
                if lookahead < characters.count, characters[lookahead] == "}" || characters[lookahead] == "]" {
                    index += 1
                    continue
                }
            }

            output.append(character)
            index += 1
        }

        return output
    }
}
