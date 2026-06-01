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
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let modified = attrs[.modificationDate] as? Date else {
                continue
            }
            if Date().timeIntervalSince(modified) > 60 {
                try? FileManager.default.removeItem(at: url)
                continue
            }

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

            // Schema v2 fields: missing kind => legacy approval payload (treat
            // as .approval and ignore questions). HookRequestKind init(rawValue:)
            // returns nil for an unknown string, so a typo in the python hook
            // also falls back to .approval rather than crashing.
            let kind: HookRequestKind = (object["kind"] as? String)
                .flatMap(HookRequestKind.init(rawValue:)) ?? .approval
            let questions: [HookInterventionQuestion]
            if let rawQuestions = object["questions"] as? [[String: Any]] {
                questions = rawQuestions.compactMap(decodeQuestion(from:))
            } else {
                questions = []
            }

            let request = HookPermissionRequest(
                id: id,
                sessionId: sessionId,
                toolName: toolName,
                projectPath: projectPath,
                summary: summary,
                matchValue: matchValue,
                receivedAt: receivedAt,
                kind: kind,
                questions: questions
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

    /// Decode one element of the `questions` JSON array written by the python
    /// hook. Mirrors the field names emitted in `bridgeScript.normalize_question`
    /// (id/header/prompt/options/isMultiple/isOther/isSecret) and tolerates
    /// missing fields so a partial payload still surfaces something.
    private static func decodeQuestion(from raw: [String: Any]) -> HookInterventionQuestion? {
        guard let id = raw["id"] as? String, !id.isEmpty else { return nil }
        let options: [HookInterventionOption]
        if let rawOptions = raw["options"] as? [[String: Any]] {
            options = rawOptions.compactMap { opt -> HookInterventionOption? in
                guard let optId = opt["id"] as? String, !optId.isEmpty else { return nil }
                return HookInterventionOption(
                    id: optId,
                    title: (opt["title"] as? String) ?? "",
                    detail: opt["detail"] as? String
                )
            }
        } else {
            options = []
        }
        return HookInterventionQuestion(
            id: id,
            header: (raw["header"] as? String) ?? "",
            prompt: (raw["prompt"] as? String) ?? "",
            detail: raw["detail"] as? String,
            options: options,
            allowsMultiple: (raw["isMultiple"] as? Bool) ?? (raw["allowsMultiple"] as? Bool) ?? false,
            allowsOther: (raw["isOther"] as? Bool) ?? (raw["allowsOther"] as? Bool) ?? false,
            isSecret: (raw["isSecret"] as? Bool) ?? false
        )
    }

    static func matchesAllowlist(request: HookPermissionRequest) -> Bool {
        // AllowlistStore is @MainActor; all callers (`pendingRequests` via
        // hookPolling Task @MainActor, `resolve` via SwiftUI button action)
        // already run on the main thread. assumeIsolated is the cheap path.
        let rules = MainActor.assumeIsolated { AllowlistStore.shared.rules }

        for rule in rules {
            guard rule.enabled else { continue }
            guard rule.toolName == request.toolName else { continue }

            if rule.scope == "session" {
                let ruleSession = rule.sessionId ?? ""
                guard !ruleSession.isEmpty, ruleSession == (request.sessionId ?? "") else { continue }
            }

            let ruleProject = rule.projectPath
            if !ruleProject.isEmpty && !request.projectPath.isEmpty {
                guard request.projectPath.hasPrefix(ruleProject) else { continue }
            }

            switch rule.matcher.kind {
            case "binaryPrefix":
                let trimmed = request.matchValue.trimmingCharacters(in: .whitespaces)
                let binary = trimmed.split(separator: " ").first.map(String.init) ?? ""
                if binary == rule.matcher.value { return true }
            case "exact":
                if request.matchValue.trimmingCharacters(in: .whitespaces)
                    == rule.matcher.value.trimmingCharacters(in: .whitespaces) {
                    return true
                }
            case "pathPrefix":
                if !request.matchValue.isEmpty, request.matchValue.hasPrefix(rule.matcher.value) {
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
            "decision": HookApprovalDecision.allow.serializedKey,
            "decidedAt": Date().timeIntervalSince1970
        ]
        if let data = try? JSONSerialization.data(withJSONObject: response, options: [.prettyPrinted, .sortedKeys]) {
            try? FileManager.default.createDirectory(at: responseDirectory, withIntermediateDirectories: true)
            try? data.write(to: responseDirectory.appendingPathComponent("\(request.id).json"), options: .atomic)
        }
        try? FileManager.default.removeItem(at: pendingDirectory.appendingPathComponent("\(request.id).json"))
    }

    static func resolve(request: HookPermissionRequest, decision: HookApprovalDecision) throws {
        try FileManager.default.createDirectory(at: responseDirectory, withIntermediateDirectories: true)
        var response: [String: Any] = [
            "id": request.id,
            "decision": decision.serializedKey,
            "decidedAt": Date().timeIntervalSince1970
        ]
        // For .answer, attach the {questionId: answer} map so the python hook
        // can emit it back as PreToolUse hookSpecificOutput.updatedInput.
        // Other decisions don't carry payload — bridgeScript's output_decision
        // only inspects "answers" when decision == "answer".
        if case .answer(let answers) = decision {
            response["answers"] = answers
        }
        let data = try JSONSerialization.data(withJSONObject: response, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: responseDirectory.appendingPathComponent("\(request.id).json"), options: .atomic)
        try? FileManager.default.removeItem(at: pendingDirectory.appendingPathComponent("\(request.id).json"))

        if decision == .alwaysAllow {
            addAllowlistRule(for: request)
        }
        if decision == .alwaysAllow || decision == .allowSession {
            if let sessionId = request.sessionId, !sessionId.isEmpty {
                addTrustedSession(sessionId)
            }
        }
    }

    private static func addAllowlistRule(for request: HookPermissionRequest) {
        let matcher: AllowlistMatcher
        if request.toolName == "Bash" {
            let binary = request.matchValue.trimmingCharacters(in: .whitespaces)
                .split(separator: " ").first.map(String.init) ?? ""
            if binary.isEmpty {
                matcher = AllowlistMatcher(kind: "toolInProject", value: "")
            } else {
                matcher = AllowlistMatcher(kind: "binaryPrefix", value: binary)
            }
        } else if ["Read", "Write", "Edit", "MultiEdit"].contains(request.toolName) {
            if !request.projectPath.isEmpty {
                matcher = AllowlistMatcher(kind: "pathPrefix", value: request.projectPath)
            } else {
                matcher = AllowlistMatcher(kind: "toolInProject", value: "")
            }
        } else {
            matcher = AllowlistMatcher(kind: "toolInProject", value: "")
        }

        let rule = AllowlistRule(
            toolName: request.toolName,
            projectPath: request.projectPath,
            scope: "always",
            enabled: true,
            matcher: matcher
        )

        // AllowlistStore.add is idempotent — duplicate (toolName, matcher,
        // projectPath) tuples are dropped on the store side.
        MainActor.assumeIsolated {
            AllowlistStore.shared.add(rule)
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
        let scriptCommand = "/usr/bin/python3 \(shellQuoted(scriptURL.path))"

        let existingEntries = hooks["PermissionRequest"] as? [[String: Any]] ?? []
        let preservedEntries = existingEntries.filter { entry in
            !containsSessionCoveCommand(entry) && !containsPingIslandCommand(entry)
        }
        let newEntry: [String: Any] = [
            "hooks": [
                [
                    "type": "command",
                    "command": scriptCommand,
                    "timeout": 86400,
                    "statusMessage": "Session Cove is waiting for approval"
                ]
            ]
        ]
        hooks["PermissionRequest"] = preservedEntries + [newEntry]

        // PreToolUse hook: same script, matcher-restricted to AskUserQuestion /
        // AskFollowupQuestion so non-question tool calls never reach our
        // process. The bridgeScript also re-checks `is_question_event` defensively
        // and exits 0 immediately for anything else.
        let existingPreToolUse = hooks["PreToolUse"] as? [[String: Any]] ?? []
        let preservedPreToolUse = existingPreToolUse.filter { entry in
            !containsSessionCoveCommand(entry) && !containsPingIslandCommand(entry)
        }
        let preToolUseEntry: [String: Any] = [
            "matcher": "AskUserQuestion|AskFollowupQuestion",
            "hooks": [
                [
                    "type": "command",
                    "command": scriptCommand,
                    "timeout": 86400,
                    "statusMessage": "Session Cove is collecting your answer"
                ]
            ]
        ]
        hooks["PreToolUse"] = preservedPreToolUse + [preToolUseEntry]

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
        SESSION_TRUST_PATH = os.path.join(ROOT, "trusted_sessions.json")
        TIMEOUT_SECONDS = 24 * 60 * 60

        def ensure_dirs():
            os.makedirs(PENDING, exist_ok=True)
            os.makedirs(RESPONSES, exist_ok=True)

        # --- Output helpers (format matches Ping Island exactly) ---

        def print_allow():
            print(json.dumps({"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}, ensure_ascii=False), flush=True)

        def default_pass_through(is_question_event):
            # Fired when the pending file disappears (Session Cove cancelled it)
            # or when we time out without a decision. Approval path -> emit allow
            # so the underlying tool keeps running. Question path -> stay silent;
            # Claude will fall back to its built-in terminal question prompt
            # rather than us injecting a guessed answer.
            if is_question_event:
                return
            print_allow()

        def output_decision(decision, is_question_event=False):
            value = decision.get("decision")
            if value == "answer":
                # AskUserQuestion / AskFollowupQuestion completion: emit the
                # PreToolUse hookSpecificOutput shape with permissionDecision
                # = allow + updatedInput carrying the answers map (questionId
                # -> user-supplied text). Claude merges updatedInput into the
                # tool_input before dispatching the actual tool call.
                answers = decision.get("answers") or {}
                print(json.dumps({
                    "hookSpecificOutput": {
                        "hookEventName": "PreToolUse",
                        "permissionDecision": "allow",
                        "updatedInput": answers,
                    }
                }, ensure_ascii=False), flush=True)
                return
            if is_question_event:
                # Question event closed without an answer (shouldn't happen via
                # the Session Cove form, but guard anyway). Stay silent so
                # Claude falls back to its terminal flow.
                return
            if value == "deny":
                obj = {"behavior": "deny", "message": "Denied in Session Cove."}
            else:
                obj = {"behavior": "allow"}
            print(json.dumps({"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":obj}}, ensure_ascii=False), flush=True)

        # --- Fast-path checks ---

        def load_trusted_sessions():
            if not os.path.exists(SESSION_TRUST_PATH):
                return set()
            try:
                with open(SESSION_TRUST_PATH, "r", encoding="utf-8") as f:
                    return set(json.load(f).get("sessions", []))
            except Exception:
                return set()

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
                    command = str(tool_input.get("command") or "") if isinstance(tool_input, dict) else ""
                    binary = command.strip().split()[0] if command.strip() else ""
                    if binary == value:
                        return True
                elif kind == "exact":
                    command = str(tool_input.get("command") or "") if isinstance(tool_input, dict) else ""
                    if command.strip() == value.strip():
                        return True
                elif kind == "pathPrefix":
                    file_path = str(tool_input.get("file_path") or tool_input.get("path") or "") if isinstance(tool_input, dict) else ""
                    if file_path and file_path.startswith(value):
                        return True
                elif kind == "toolInProject":
                    return True

            return False

        # --- Helpers ---

        def stable_summary(payload):
            tool_name = str(payload.get("tool_name") or "Tool")
            tool_input = payload.get("tool_input") or {}
            if isinstance(tool_input, dict):
                for key in ("command", "file_path", "path", "url", "description"):
                    v = tool_input.get(key)
                    if v:
                        return f"{tool_name}: {str(v)[:220]}"
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

        def normalize_question(raw, idx):
            # Map Claude's AskUserQuestion shape (question/header/options/multiSelect)
            # onto Session Cove's HookInterventionQuestion field names. Unknown
            # input shapes degrade to a free-text prompt instead of dropping the
            # question entirely.
            if not isinstance(raw, dict):
                return {
                    "id": "q{}".format(idx + 1),
                    "header": "",
                    "prompt": str(raw or ""),
                    "options": [],
                    "isMultiple": False,
                    "isOther": False,
                    "isSecret": False,
                }
            qid = str(raw.get("id") or "q{}".format(idx + 1))
            options = []
            raw_options = raw.get("options") or []
            if isinstance(raw_options, list):
                for opt_idx, opt in enumerate(raw_options):
                    if not isinstance(opt, dict):
                        continue
                    detail = opt.get("description") or opt.get("detail")
                    options.append({
                        "id": str(opt.get("id") or "{}-o{}".format(qid, opt_idx + 1)),
                        "title": str(opt.get("label") or opt.get("title") or ""),
                        "detail": str(detail) if detail else None,
                    })
            return {
                "id": qid,
                "header": str(raw.get("header") or ""),
                "prompt": str(raw.get("question") or raw.get("prompt") or ""),
                "options": options,
                "isMultiple": bool(raw.get("multiSelect") or raw.get("allowsMultiple")),
                "isOther": bool(raw.get("allowsOther")),
                "isSecret": bool(raw.get("isSecret")),
            }

        def build_questions(payload):
            # AskUserQuestion uses tool_input.questions: [{question, header,
            # options, multiSelect}]. AskFollowupQuestion (older / single-shot
            # variant) may carry a single string under tool_input.question;
            # synthesize a one-question free-text fallback for that case.
            tool_input = payload.get("tool_input") or {}
            if not isinstance(tool_input, dict):
                return []
            raw_questions = tool_input.get("questions")
            if isinstance(raw_questions, list) and raw_questions:
                return [normalize_question(q, idx) for idx, q in enumerate(raw_questions)]
            single = tool_input.get("question")
            if isinstance(single, str) and single:
                return [{
                    "id": "q1",
                    "header": str(tool_input.get("header") or "Answer"),
                    "prompt": single,
                    "options": [],
                    "isMultiple": False,
                    "isOther": True,
                    "isSecret": False,
                }]
            return []

        def make_request_id(payload):
            stable = {
                "tool_name": payload.get("tool_name"),
                "tool_input": payload.get("tool_input"),
                "cwd": payload.get("cwd"),
            }
            seed = json.dumps(stable, ensure_ascii=False, sort_keys=True, default=str)
            return hashlib.sha256(seed.encode("utf-8")).hexdigest()[:24]

        # --- Main ---

        def main():
            ensure_dirs()
            raw = sys.stdin.read()
            if not raw.strip():
                return 0
            try:
                payload = json.loads(raw)
            except Exception:
                return 0

            event_name = payload.get("hook_event_name")
            tool_name = str(payload.get("tool_name") or "")
            is_question_tool = tool_name in ("AskUserQuestion", "AskFollowupQuestion")
            # Two events feed Session Cove now: legacy PermissionRequest
            # (yes/deny/always) and PreToolUse for the interactive question
            # tools. The Claude settings.json matcher already restricts
            # PreToolUse traffic to those two tool names, but we re-check here
            # so a wildcard registration upstream can't accidentally drown the
            # script in unrelated PreToolUse calls.
            is_question_event = event_name == "PreToolUse" and is_question_tool

            if event_name != "PermissionRequest" and not is_question_event:
                return 0

            session_id = str(payload.get("session_id") or "")

            # Allowlist + trusted-session shortcuts only apply to the legacy
            # approval path. Question events always surface in the UI so the
            # user can answer; nothing to "pre-approve" for them.
            if not is_question_event:
                if match_allowlist(payload):
                    print_allow()
                    return 0
                if session_id and session_id in load_trusted_sessions():
                    print_allow()
                    return 0

            request_id = make_request_id(payload)
            request_path = os.path.join(PENDING, f"{request_id}.json")
            response_path = os.path.join(RESPONSES, f"{request_id}.json")

            try:
                os.remove(response_path)
            except OSError:
                pass

            request = {
                "id": request_id,
                "sessionId": session_id,
                "toolName": tool_name or "Tool",
                "projectPath": str(payload.get("cwd") or os.getcwd()),
                "summary": stable_summary(payload),
                "matchValue": extract_match_value(payload),
                "receivedAt": time.time(),
            }
            if is_question_event:
                request.update({
                    "kind": "question",
                    "schemaVersion": 2,
                    "expectsAnswer": True,
                    "questions": build_questions(payload),
                })

            tmp = request_path + ".tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(request, f, ensure_ascii=False, indent=2, sort_keys=True)
            os.replace(tmp, request_path)

            deadline = time.time() + TIMEOUT_SECONDS
            while time.time() < deadline:
                if os.path.exists(response_path):
                    with open(response_path, "r", encoding="utf-8") as f:
                        decision = json.load(f)
                    output_decision(decision, is_question_event=is_question_event)
                    try:
                        os.remove(request_path)
                    except OSError:
                        pass
                    try:
                        os.remove(response_path)
                    except OSError:
                        pass
                    return 0
                if not os.path.exists(request_path):
                    default_pass_through(is_question_event)
                    return 0
                time.sleep(0.2)
            default_pass_through(is_question_event)
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
