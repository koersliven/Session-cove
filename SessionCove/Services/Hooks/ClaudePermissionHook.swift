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

        // Clear stale pending files left over from prior hook script versions —
        // the python scripts that wrote them are long-dead and won't poll for our response.
        if let stale = try? fileManager.contentsOfDirectory(at: pendingDirectory, includingPropertiesForKeys: nil) {
            for url in stale where url.pathExtension == "json" {
                try? fileManager.removeItem(at: url)
            }
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

        var visible: [HookPermissionRequest] = []

        for url in files where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = object["id"] as? String,
                  let toolName = object["toolName"] as? String,
                  let projectPath = object["projectPath"] as? String,
                  let summary = object["summary"] as? String else {
                continue
            }

            let sessionId = object["sessionId"] as? String
            let matchValue = object["matchValue"] as? String ?? ""
            let receivedAt = (object["receivedAt"] as? TimeInterval).map(Date.init(timeIntervalSince1970:)) ?? Date()
            let request = HookPermissionRequest(
                id: id,
                sessionId: sessionId,
                toolName: toolName,
                projectPath: projectPath,
                summary: summary,
                matchValue: matchValue,
                receivedAt: receivedAt
            )

            // UI-side allowlist guard: even if the python hook missed the match
            // (stale pending file from old script, race, etc.) — silently auto-allow
            // matching requests so the UI never shows a popup the user already pre-approved.
            if matchesAllowlist(request: request) {
                autoResolveAllowed(request: request)
                continue
            }

            visible.append(request)
        }

        return visible.sorted { $0.receivedAt < $1.receivedAt }
    }

    static func matchesAllowlist(request: HookPermissionRequest) -> Bool {
        guard let data = try? Data(contentsOf: allowlistURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rules = json["rules"] as? [[String: Any]] else {
            return false
        }

        for rule in rules {
            let enabled = rule["enabled"] as? Bool ?? true
            guard enabled else { continue }
            guard let toolName = rule["toolName"] as? String, toolName == request.toolName else { continue }

            let scope = rule["scope"] as? String ?? "always"
            if scope == "session" {
                let ruleSession = rule["sessionId"] as? String ?? ""
                guard !ruleSession.isEmpty, ruleSession == (request.sessionId ?? "") else { continue }
            }

            let ruleProject = rule["projectPath"] as? String ?? ""
            if !ruleProject.isEmpty && !request.projectPath.isEmpty {
                guard request.projectPath.hasPrefix(ruleProject) else { continue }
            }

            guard let matcher = rule["matcher"] as? [String: String],
                  let kind = matcher["kind"],
                  let value = matcher["value"] else { continue }

            switch kind {
            case "binaryPrefix":
                let trimmed = request.matchValue.trimmingCharacters(in: .whitespaces)
                let binary = trimmed.split(separator: " ").first.map(String.init) ?? ""
                if binary == value { return true }
            case "exact":
                if request.matchValue.trimmingCharacters(in: .whitespaces)
                    == value.trimmingCharacters(in: .whitespaces) {
                    return true
                }
            case "pathPrefix":
                if !request.matchValue.isEmpty, request.matchValue.hasPrefix(value) {
                    return true
                }
            case "toolInProject":
                return true
            default:
                continue
            }
        }
        return false
    }

    /// Silently resolve a pending request that matches the allowlist —
    /// writes a response (in case a python hook is still polling) and removes the pending file.
    private static func autoResolveAllowed(request: HookPermissionRequest) {
        let response: [String: Any] = [
            "id": request.id,
            "decision": HookApprovalDecision.allow.rawValue,
            "decidedAt": Date().timeIntervalSince1970
        ]
        if let data = try? JSONSerialization.data(withJSONObject: response, options: [.prettyPrinted, .sortedKeys]) {
            try? FileManager.default.createDirectory(at: responseDirectory, withIntermediateDirectories: true)
            try? data.write(to: responseDirectory.appendingPathComponent("\(request.id).json"), options: .atomic)
        }
        try? FileManager.default.removeItem(at: pendingDirectory.appendingPathComponent("\(request.id).json"))
    }

    private static let allowlistURL = hookDirectory.appendingPathComponent("allowlist.json")

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

        if decision == .alwaysAllow || decision == .allowSession {
            saveToAllowlist(request: request, scope: decision == .alwaysAllow ? "always" : "session")
        }
        if decision == .allowSession, let sessionId = request.sessionId, !sessionId.isEmpty {
            addTrustedSession(sessionId)
        }
    }

    private static let trustedSessionsURL = hookDirectory.appendingPathComponent("trusted_sessions.json")

    private static func addTrustedSession(_ sessionId: String) {
        var sessions: [String] = []
        if let data = try? Data(contentsOf: trustedSessionsURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let existing = json["sessions"] as? [String] {
            sessions = existing
        }
        guard !sessions.contains(sessionId) else { return }
        sessions.append(sessionId)
        let payload: [String: Any] = ["sessions": sessions]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: trustedSessionsURL, options: .atomic)
        }
    }

    private static func saveToAllowlist(request: HookPermissionRequest, scope: String) {
        let matcher = deriveMatcherRule(toolName: request.toolName, matchValue: request.matchValue)
        let rule: [String: Any] = [
            "id": "rule_\(UUID().uuidString.prefix(12).lowercased())",
            "enabled": true,
            "scope": scope,
            "toolName": request.toolName,
            "matcher": matcher,
            "projectPath": request.projectPath,
            "sessionId": request.sessionId ?? "",
            "createdAt": Date().timeIntervalSince1970,
            "sourceRequest": [
                "id": request.id,
                "summary": request.summary
            ]
        ]

        var allowlist = readAllowlist()
        allowlist.append(rule)
        writeAllowlist(allowlist)
    }

    private static func deriveMatcherRule(toolName: String, matchValue: String) -> [String: String] {
        switch toolName {
        case "Bash":
            let command = matchValue.trimmingCharacters(in: .whitespaces)
            let binary = command.split(separator: " ").first.map(String.init) ?? command
            let safeBinaries: Set<String> = [
                "git", "ls", "cat", "grep", "find", "npm", "yarn", "swift", "python3",
                "python", "head", "tail", "echo", "pwd", "mkdir", "which", "wc", "sort",
                "diff", "xcodebuild", "open", "cp", "mv", "touch", "chmod", "man"
            ]
            if safeBinaries.contains(binary) {
                return ["kind": "binaryPrefix", "value": binary]
            }
            return ["kind": "exact", "value": command]
        case "Read", "Glob", "Grep", "LS":
            return ["kind": "toolInProject", "value": ""]
        case "Edit", "Write", "MultiEdit":
            if !matchValue.isEmpty {
                let dir = (matchValue as NSString).deletingLastPathComponent
                return ["kind": "pathPrefix", "value": dir]
            }
            return ["kind": "toolInProject", "value": ""]
        default:
            return ["kind": "toolInProject", "value": ""]
        }
    }

    private static func readAllowlist() -> [[String: Any]] {
        guard let data = try? Data(contentsOf: allowlistURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rules = json["rules"] as? [[String: Any]] else {
            return []
        }
        return rules
    }

    private static func writeAllowlist(_ rules: [[String: Any]]) {
        let allowlist: [String: Any] = ["version": 1, "rules": rules]
        guard let data = try? JSONSerialization.data(withJSONObject: allowlist, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }
        try? data.write(to: allowlistURL, options: .atomic)
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
        let preservedEntries = existingEntries.filter { entry in
            !containsSessionCoveCommand(entry) && !containsPingIslandCommand(entry)
        }
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

    private static func containsPingIslandCommand(_ entry: [String: Any]) -> Bool {
        if (entry["command"] as? String)?.contains("ping-island") == true {
            return true
        }

        if let nested = entry["hooks"] as? [[String: Any]] {
            return nested.contains { containsPingIslandCommand($0) }
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
        ALLOWLIST_PATH = os.path.join(ROOT, "allowlist.json")
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

        def extract_match_value(payload):
            tool_name = str(payload.get("tool_name") or "")
            tool_input = payload.get("tool_input") or {}
            if not isinstance(tool_input, dict):
                return ""
            if tool_name == "Bash":
                return str(tool_input.get("command") or "")
            if tool_name in ("Read", "Write", "Edit", "MultiEdit"):
                return str(tool_input.get("file_path") or tool_input.get("path") or "")
            return ""

        def make_request_id(payload):
            # Use a stable seed based on payload content to avoid flashing on reload
            seed = json.dumps(payload, ensure_ascii=False, sort_keys=True, default=str)
            return hashlib.sha256(seed.encode("utf-8")).hexdigest()[:24]

        def match_allowlist(payload):
            if not os.path.exists(ALLOWLIST_PATH):
                return False
            try:
                with open(ALLOWLIST_PATH, "r", encoding="utf-8") as f:
                    allowlist = json.load(f)
            except Exception:
                return False

            rules = allowlist.get("rules") or []
            tool_name = str(payload.get("tool_name") or "")
            tool_input = payload.get("tool_input") or {}
            project_path = str(payload.get("cwd") or "")
            session_id = str(payload.get("session_id") or "")

            for rule in rules:
                if not rule.get("enabled", True):
                    continue
                if rule.get("toolName") != tool_name:
                    continue

                scope = rule.get("scope", "always")
                if scope == "session":
                    rule_session = rule.get("sessionId", "")
                    if not rule_session or rule_session != session_id:
                        continue

                rule_project = rule.get("projectPath", "")
                if rule_project and project_path and not project_path.startswith(rule_project):
                    continue

                matcher = rule.get("matcher") or {}
                kind = matcher.get("kind", "")
                value = matcher.get("value", "")

                if kind == "binaryPrefix":
                    command = ""
                    if isinstance(tool_input, dict):
                        command = str(tool_input.get("command") or "")
                    binary = command.strip().split()[0] if command.strip() else ""
                    if binary == value:
                        return True
                elif kind == "exact":
                    command = ""
                    if isinstance(tool_input, dict):
                        command = str(tool_input.get("command") or "")
                    if command.strip() == value.strip():
                        return True
                elif kind == "pathPrefix":
                    file_path = ""
                    if isinstance(tool_input, dict):
                        file_path = str(tool_input.get("file_path") or tool_input.get("path") or "")
                    if file_path and file_path.startswith(value):
                        return True
                elif kind == "toolInProject":
                    return True

            return False

        SESSION_TRUST_PATH = os.path.join(ROOT, "trusted_sessions.json")

        def load_trusted_sessions():
            if not os.path.exists(SESSION_TRUST_PATH):
                return set()
            try:
                with open(SESSION_TRUST_PATH, "r", encoding="utf-8") as f:
                    return set(json.load(f).get("sessions", []))
            except Exception:
                return set()

        def print_allow():
            hook_output = {
                "hookEventName": "PermissionRequest",
                "decision": {"behavior": "allow"}
            }
            print(json.dumps({"hookSpecificOutput": hook_output}, ensure_ascii=False), flush=True)

        def output_decision(decision):
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
            elif value == "alwaysAllow":
                hook_output["decision"] = {"behavior": "always"}
            else:
                hook_output["decision"] = {"behavior": "allow"}
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

            if match_allowlist(payload):
                print_allow()
                return 0

            session_id = str(payload.get("session_id") or "")
            if session_id and session_id in load_trusted_sessions():
                print_allow()
                return 0

            request_id = make_request_id(payload)
            request_path = os.path.join(PENDING, f"{request_id}.json")
            response_path = os.path.join(RESPONSES, f"{request_id}.json")
            request = {
                "id": request_id,
                "sessionId": str(payload.get("session_id") or ""),
                "toolName": str(payload.get("tool_name") or "Tool"),
                "projectPath": str(payload.get("cwd") or os.getcwd()),
                "summary": stable_summary(payload),
                "matchValue": extract_match_value(payload),
                "receivedAt": time.time(),
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
                    output_decision(decision)
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
