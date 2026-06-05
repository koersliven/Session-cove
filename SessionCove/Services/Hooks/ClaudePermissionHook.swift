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

    /// Top-level install entry point. Always runs the shared Session Cove
    /// bootstrap (directories + bridge script) and then fans out to the
    /// per-provider settings-file installers for every id present in
    /// `CoveSettings.shared.enabledProviders`.
    ///
    /// Per-provider work is isolated inside `installFor<Provider>()` so a
    /// failure on one provider's settings file does not abort the others.
    /// First-launch default is `["claude"]`, so calling this on a fresh
    /// machine touches only `~/.claude/settings.json` (bit-for-bit
    /// equivalent to the legacy `install()`).
    @MainActor
    static func install() throws {
        try ensureSessionCoveBootstrap()
        let enabled = CoveSettings.shared.enabledProviders

        if enabled.contains("claude") {
            try? installForClaude()
        }
        if enabled.contains("qoder") {
            try? installForQoder()
        }
        if enabled.contains("qoderwork") {
            try? installForQoderWork()
        }
        if enabled.contains("cursor") {
            try? installForCursor()
        }
    }

    /// Install the Session Cove hook into `~/.claude/settings.json`.
    /// Public so the AI 框架 settings tab can re-run a single provider
    /// without iterating the whole enabled set (e.g. when the user
    /// presses a per-row "Reinstall" affordance).
    static func installForClaude() throws {
        try writeClaudeStyleSettings(
            settingsURL: claudeSettingsURL,
            providerArg: "claude"
        )
    }

    static func installForQoder() throws {
        try writeClaudeStyleSettings(
            settingsURL: qoderSettingsURL,
            providerArg: "qoder"
        )
    }

    static func installForQoderWork() throws {
        try writeClaudeStyleSettings(
            settingsURL: qoderWorkSettingsURL,
            providerArg: "qoderwork"
        )
    }

    /// Install the Session Cove stop hook into `~/.cursor/hooks.json`.
    /// Cursor uses a wrapped or flat schema — we detect a top-level
    /// `hooks` dict and merge inside it so the user's `version: 1` and
    /// any sibling keys survive verbatim.
    static func installForCursor() throws {
        try writeCursorHooks(install: true)
    }

    /// Reverse the install for a single provider. Removes every Session
    /// Cove-owned entry from that framework's settings file but leaves
    /// pre-existing user entries (r2c hooks, audit scripts, etc.) verbatim.
    /// Called by `WindowManager` when the user disables a provider in the
    /// AI 框架 tab.
    ///
    /// Unknown providerIds are no-ops. Missing settings files are no-ops
    /// (nothing to clean). Errors are swallowed because uninstall is
    /// best-effort cleanup; surfacing a UserDefaults-persisted toggle to
    /// "back off" because of disk failure would be confusing.
    static func uninstall(providerId: String) {
        switch providerId {
        case "claude":
            try? removeFromClaudeStyleSettings(settingsURL: claudeSettingsURL)
        case "qoder":
            try? removeFromClaudeStyleSettings(settingsURL: qoderSettingsURL)
        case "qoderwork":
            try? removeFromClaudeStyleSettings(settingsURL: qoderWorkSettingsURL)
        case "cursor":
            try? writeCursorHooks(install: false)
        default:
            return
        }
    }

    /// Quick "is the Session Cove hook command present in this provider's
    /// settings file?" check used by the AI 框架 tab to render a status
    /// dot. Reads the file as bytes and substring-matches the marker so
    /// it works regardless of whether the file is wrapped/flat/JSON5.
    static func isInstalled(providerId: String) -> Bool {
        let url: URL?
        switch providerId {
        case "claude":    url = claudeSettingsURL
        case "qoder":     url = qoderSettingsURL
        case "qoderwork": url = qoderWorkSettingsURL
        case "cursor":    url = cursorHooksURL
        default:          return false
        }
        guard let url, let data = try? Data(contentsOf: url) else {
            return false
        }
        return containsSessionCoveCommandInData(data)
    }

    /// Shared bootstrap: hook scratch directories + bridge script. Idempotent.
    /// Split out so provider toggles in the AI 框架 tab can call install
    /// for an individual provider without re-running this every time (the
    /// top-level `install()` still calls it once on app launch).
    private static func ensureSessionCoveBootstrap() throws {
        let fileManager = FileManager.default
        try [supportDirectory, hookDirectory, pendingDirectory, responseDirectory, binDirectory].forEach { url in
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }

        // DON'T clear pending files on startup — a Python hook may be
        // actively blocking (poll-waiting for our response) right now.
        // The per-kind TTL sweep in `pendingRequests()` handles genuinely
        // stale files (24h for approval, 1h for completion). Clearing here
        // would kill any in-flight AskUserQuestion hook that's waiting for
        // the user to answer in the SC popup.

        try bridgeScript.data(using: .utf8)?.write(to: scriptURL, options: .atomic)
    }

    // MARK: - Per-provider settings paths

    private static var claudeSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    private static var qoderSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".qoder", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    private static var qoderWorkSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".qoderwork", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    private static var cursorHooksURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor", isDirectory: true)
            .appendingPathComponent("hooks.json")
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

            // Per-kind staleness: approval/question polls every 30s and the
            // python script touches mtime to keep the file alive — 24h is
            // safe. Completion is fire-and-forget; nothing refreshes mtime,
            // so a 1h cap keeps abandoned toasts from accumulating.
            let ttl: TimeInterval = (kind == .completion) ? (60 * 60) : (24 * 60 * 60)
            if Date().timeIntervalSince(modified) > ttl {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            let questions: [HookInterventionQuestion]
            if let rawQuestions = object["questions"] as? [[String: Any]] {
                questions = rawQuestions.compactMap(decodeQuestion(from:))
            } else {
                questions = []
            }

            let toolInputJSON = object["toolInputJSON"] as? String
            let toolInputTruncated = (object["toolInputTruncated"] as? Bool) ?? false
            let transcriptPath = object["transcriptPath"] as? String
            let completedAt = (object["completedAt"] as? TimeInterval).map(Date.init(timeIntervalSince1970:))
            let lastMessagePreview = object["lastMessagePreview"] as? String
            // Schema v3 added providerId. Older payloads without the field
            // are written by the legacy Claude-only python hook, so default
            // to "claude" — the only provider currently registered.
            let providerId = (object["providerId"] as? String) ?? "claude"

            let request = HookPermissionRequest(
                id: id,
                sessionId: sessionId,
                toolName: toolName,
                projectPath: projectPath,
                summary: summary,
                matchValue: matchValue,
                receivedAt: receivedAt,
                providerId: providerId,
                kind: kind,
                questions: questions,
                toolInputJSON: toolInputJSON,
                toolInputTruncated: toolInputTruncated,
                transcriptPath: transcriptPath,
                completedAt: completedAt,
                lastMessagePreview: lastMessagePreview
            )

            // UI-side allowlist guard: even if the python hook missed the match
            // (stale pending file from old script, race, etc.) — silently auto-allow
            // matching requests so the UI never shows a popup the user already pre-approved.
            // Skip this branch for completion AND question kinds:
            //   - completion (Stop): not allowlist-eligible.
            //   - question (AskUserQuestion): must always surface the form so the
            //     user can provide answers. "Always allow" is a permission concept,
            //     not a question-bypassing concept — auto-resolving a question
            //     would eat the pending and Claude never gets an answer.
            if kind == .approval {
                if matchesAllowlist(request: request) {
                    autoResolveAllowed(request: request)
                    continue
                }
                // Trusted-session guard. Without this, concurrent
                // PermissionRequests from the same Claude turn race each
                // other: Python A and Python B both check trusted before
                // either has been added; user clicks Always on A, Swift
                // adds the sessionId to trusted_sessions, but B's pending
                // file is already on disk waiting for a response that the
                // trusted-session shortcut would otherwise handle. Each
                // poll re-reads the file, so once Always is pressed, every
                // subsequent unresolved pending for the same session
                // collapses silently here.
                if let sessionId = request.sessionId,
                   !sessionId.isEmpty,
                   isSessionTrusted(sessionId) {
                    autoResolveAllowed(request: request)
                    continue
                }
            }

            visible.append(request)
        }

        // Sort approval/question before completion so a pending approval
        // always wins the .first slot — completion toasts wait until the
        // user resolves the blocker. Within each group, oldest first.
        return visible.sorted { lhs, rhs in
            if lhs.kind != rhs.kind {
                if lhs.kind == .completion { return false }
                if rhs.kind == .completion { return true }
            }
            return lhs.receivedAt < rhs.receivedAt
        }
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
            // Provider isolation: a Cursor session must never match a Claude
            // allowlist rule (and vice versa). Both sides default to "claude"
            // today so existing flows are unaffected.
            guard rule.providerId == request.providerId else { continue }
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
        // Completion-toast (Stop hook) is fire-and-forget — the Python script
        // exits immediately after writing the pending file. Nothing on the
        // other end is waiting to read a response, so just remove the
        // pending file. Mock requests with id prefix `stop-mock-` go through
        // the same path; FileManager silently ignores missing files.
        if request.kind == .completion {
            try? FileManager.default.removeItem(
                at: pendingDirectory.appendingPathComponent("\(request.id).json")
            )
            return
        }

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
        //
        // Terminal injection path (v4+): when `useTerminalInjection` is true,
        // the Python bridge stays SILENT on stdout for question events — Claude
        // falls back to its built-in terminal prompt and TerminalTextInjector
        // types the answer. The bridge still reads the response file to exit
        // its poll loop cleanly.
        //
        // Answer delivery is now 100% through the Python hook stdout path.
        // Python blocking-polls for this response file, reads the answers,
        // emits updatedInput to Claude's stdout. No terminal injection,
        // no pty write — just the file + hook stdout protocol.
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
            matcher: matcher,
            providerId: request.providerId
        )

        // AllowlistStore.add is idempotent — duplicate (toolName, matcher,
        // projectPath) tuples are dropped on the store side.
        MainActor.assumeIsolated {
            AllowlistStore.shared.add(rule)
        }
    }

    private static let trustedSessionsURL = hookDirectory.appendingPathComponent("trusted_sessions.json")

    /// Re-reads `trusted_sessions.json` on every call so a Just-pressed
    /// "Always" instantly affects pending files on the next poll tick.
    /// Cheap (the file is small and the directory is local). Returns
    /// false on any read/parse error — the popup still surfaces in that
    /// case, which is the safe default.
    static func isSessionTrusted(_ sessionId: String) -> Bool {
        guard let data = try? Data(contentsOf: trustedSessionsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessions = json["sessions"] as? [String] else {
            return false
        }
        return sessions.contains(sessionId)
    }

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


    /// Shared writer for Claude / Qoder / QoderWork — all three frameworks
    /// share the same `settings.json` schema (PermissionRequest + PreToolUse
    /// + Stop hook arrays under a top-level `hooks` dict) and the same
    /// Python bridge script. The only thing that varies is the file path
    /// and the `--provider <id>` argument that tells the bridge which
    /// stdout dialect to emit. Atomic write via tmp-file replace.
    private static func writeClaudeStyleSettings(
        settingsURL: URL,
        providerArg: String
    ) throws {
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let existingData = try? Data(contentsOf: settingsURL)
        var root: [String: Any] = existingData.flatMap(HookConfigParser.parseJSONObject(from:)) ?? [:]
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        // `--provider <id>` tells the bridge script which dialect to emit
        // on stdout. Schema v4 routes via the bridge's DIALECTS table.
        let scriptCommand = "/usr/bin/python3 \(shellQuoted(scriptURL.path)) --provider \(providerArg)"

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

        // Stop hook: same script, fire-and-forget. The bridgeScript writes a
        // .completion request and exits 0 immediately — no response file, no
        // poll loop. timeout is short (5s) since the work is just a file
        // write. We strip ping-island's Stop entry too — the user opted for
        // Session Cove to take over completion notifications (matches the
        // PermissionRequest/PreToolUse policy).
        let existingStop = hooks["Stop"] as? [[String: Any]] ?? []
        let preservedStop = existingStop.filter { entry in
            !containsSessionCoveCommand(entry) && !containsPingIslandCommand(entry)
        }
        let stopEntry: [String: Any] = [
            "hooks": [
                [
                    "type": "command",
                    "command": scriptCommand,
                    "timeout": 5
                ]
            ]
        ]
        hooks["Stop"] = preservedStop + [stopEntry]

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
        try atomicWrite(data, to: settingsURL)
    }

    /// Strip every Session Cove-owned entry from a Claude-style settings
    /// file (Claude / Qoder / QoderWork share the schema). Pre-existing
    /// user entries in PermissionRequest / PreToolUse / Stop arrays are
    /// preserved verbatim. Empty arrays are dropped from the output so we
    /// don't leave hollow `"Stop": []` artifacts behind.
    ///
    /// No-op if the file is missing or unparseable.
    private static func removeFromClaudeStyleSettings(settingsURL: URL) throws {
        guard let existingData = try? Data(contentsOf: settingsURL) else { return }
        guard var root = HookConfigParser.parseJSONObject(from: existingData) else { return }
        guard var hooks = root["hooks"] as? [String: Any] else { return }

        for event in ["PermissionRequest", "PreToolUse", "Stop"] {
            guard let entries = hooks[event] as? [[String: Any]] else { continue }
            let preserved = entries.filter { entry in
                !containsSessionCoveCommand(entry)
            }
            if preserved.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = preserved
            }
        }

        if hooks.isEmpty {
            root.removeValue(forKey: "hooks")
        } else {
            root["hooks"] = hooks
        }

        var options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys]
        options.insert(.withoutEscapingSlashes)
        let data = try JSONSerialization.data(withJSONObject: root, options: options)
        try atomicWrite(data, to: settingsURL)
    }

    /// Write (or strip from) `~/.cursor/hooks.json`. Cursor's schema is
    /// either flat `{"<event>": [...]}` or wrapped `{"hooks":{"<event>":[...]}, "version":1}`
    /// depending on how the file was first generated. We detect a
    /// top-level `hooks` dict and merge INSIDE it so wrapper-only keys
    /// (`version`, etc.) survive.
    ///
    /// Whitelist guard: refuse to mutate the file if it does not parse as
    /// a JSON object — this keeps a corrupt or YAML-shaped file from
    /// being silently overwritten with our merged structure.
    private static func writeCursorHooks(install: Bool) throws {
        let settingsURL = cursorHooksURL
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let existingData = try? Data(contentsOf: settingsURL)

        // Backup the original ONCE before our first mutation. Skip if the
        // file already contains our marker — that means we wrote it on a
        // prior install and the "real" pre-Session-Cove file is already
        // backed up (or never existed).
        if install, let existingData, !containsSessionCoveCommandInData(existingData) {
            let backupURL = settingsURL.deletingLastPathComponent()
                .appendingPathComponent("settings.session-cove-backup.json")
            if !FileManager.default.fileExists(atPath: backupURL.path) {
                try? existingData.write(to: backupURL, options: .atomic)
            }
        }

        // Parse — fall back to empty wrapped shape on missing file.
        let root: [String: Any] = existingData.flatMap(HookConfigParser.parseJSONObject(from:)) ?? [:]

        // Detect wrapped vs flat: if top-level has a `hooks` dict, merge
        // inside it. The actual file the user shipped has a wrapper plus
        // a `"version": 1` sibling, so we MUST preserve those.
        let isWrapped = (root["hooks"] as? [String: Any]) != nil

        let scriptCommand = "/usr/bin/python3 \(shellQuoted(scriptURL.path)) --provider cursor"

        var newRoot = root
        if isWrapped {
            let inner = (root["hooks"] as? [String: Any]) ?? [:]
            let merged = install
                ? CursorHooksMerger.merged(into: inner, sessionCoveCommand: scriptCommand)
                : CursorHooksMerger.removed(from: inner)
            if merged.isEmpty {
                newRoot.removeValue(forKey: "hooks")
            } else {
                newRoot["hooks"] = merged
            }
        } else {
            // Flat shape — operate on the top level directly. If the file
            // was empty (no existing data) and we're uninstalling, write
            // nothing back.
            let merged = install
                ? CursorHooksMerger.merged(into: root, sessionCoveCommand: scriptCommand)
                : CursorHooksMerger.removed(from: root)
            newRoot = merged
        }

        // Uninstall + originally-empty file ⇒ skip the write so we don't
        // create an empty `{}` hooks.json the user never had.
        if !install, existingData == nil { return }

        var options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys]
        options.insert(.withoutEscapingSlashes)
        let data = try JSONSerialization.data(withJSONObject: newRoot, options: options)
        try atomicWrite(data, to: settingsURL)
    }

    /// Atomic write helper: write to a sibling tmp file then `replaceItemAt`
    /// to swap. Avoids the half-written-file failure mode if the process
    /// is killed mid-write — important for files like `~/.claude/settings.json`
    /// that the agent itself reads on every tool call.
    private static func atomicWrite(_ data: Data, to url: URL) throws {
        let tmpURL = url.appendingPathExtension("sc-tmp")
        try data.write(to: tmpURL, options: .atomic)
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: tmpURL)
            } else {
                try FileManager.default.moveItem(at: tmpURL, to: url)
            }
        } catch {
            try? FileManager.default.removeItem(at: tmpURL)
            throw error
        }
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

        # Schema v4 (2026-06-03): bridgeScript now accepts `--provider <id>`
        # and routes stdout through a per-provider DIALECTS table. The
        # `providerId` field on each request mirrors the parsed flag.
        # Older v2/v3 payloads still decode on the Swift side via
        # decodeIfPresent (legacy files default providerId to "claude").
        SCHEMA_VERSION = 4
        # tool_input serialization cap. 8 KB is generous for shell commands +
        # most Edit diffs, and small enough that SwiftUI Text + ScrollView
        # render without slowdown. MCP payloads larger than this get truncated.
        TOOL_INPUT_SIZE_CAP = 8192
        # Redact dict values whose keys hint at credentials. Heuristic, not
        # exhaustive — covers obvious cases like Authorization headers and
        # API token kwargs. Documented in the Plan's risks.
        SECRET_KEY_PATTERNS = ("token", "password", "secret", "auth", "api_key", "authorization", "bearer")

        def ensure_dirs():
            os.makedirs(PENDING, exist_ok=True)
            os.makedirs(RESPONSES, exist_ok=True)

        # --- Provider dialects ---------------------------------------------
        # Each provider registers two emitters keyed by event class:
        #   permission(decision) — stdout for legacy approval-style hooks.
        #     `decision` is the dict written by Swift, or None for
        #     pass-through/allow shortcuts.
        #   question(decision, tool_input) — stdout for typed-answer hooks.
        # The legacy claude path (PermissionRequest + PreToolUse stdout
        # shapes) is preserved bit-for-bit by emit_claude_*.

        DEBUG_LOG_PATH = os.path.expanduser("~/.session-cove/hooks/debug.log")

        def debug_log(msg):
            try:
                if os.path.exists(DEBUG_LOG_PATH) and os.path.getsize(DEBUG_LOG_PATH) > 1_000_000:
                    os.remove(DEBUG_LOG_PATH)
                with open(DEBUG_LOG_PATH, "a", encoding="utf-8") as f:
                    f.write("{} pid={} {}\\n".format(
                        time.strftime("%H:%M:%S"), os.getpid(), msg))
            except OSError:
                pass

        def emit_claude_permission(decision):
            is_deny = isinstance(decision, dict) and decision.get("decision") == "deny"
            behavior = "deny" if is_deny else "allow"
            message = "Denied in Session Cove." if is_deny else None
            inner = {"behavior": behavior}
            if message:
                inner["message"] = message
            output = {
                "hookSpecificOutput": {
                    "hookEventName": "PermissionRequest",
                    "decision": inner,
                    "permissionDecision": behavior,
                }
            }
            if message:
                output["hookSpecificOutput"]["permissionDecisionReason"] = message
            payload = json.dumps(output, ensure_ascii=False)
            debug_log("emit_permission stdout=" + payload)
            print(payload, flush=True)

        def emit_claude_question(decision, tool_input):
            # Question event closed without an answer (timeout, Session Cove
            # cancellation, or guard against a non-answer decision sneaking in)
            # — stay silent so Claude falls back to its built-in terminal
            # question flow rather than us injecting a guessed answer.
            if not isinstance(decision, dict) or decision.get("decision") != "answer":
                return
            # (useTerminalInjection flag removed — terminal injection approach
            # was disproven. All answers now flow through hook stdout.)
            # Fallback path: terminal injection failed or not requested.
            # AskUserQuestion / AskFollowupQuestion completion. Claude's
            # PreToolUse hookSpecificOutput.updatedInput **replaces the
            # entire tool_input** before dispatch — earlier we wrote just
            # `{"answers": {...}}` and Claude rejected the call with
            # "required parameter `questions` is missing" because we'd
            # wiped the original schema. Echo the original tool_input
            # back and append `answers` alongside, so all required
            # fields (questions, etc.) survive.
            answers = decision.get("answers") or {}
            merged = dict(tool_input) if isinstance(tool_input, dict) else {}
            merged["answers"] = answers
            # Format from ping-island (verified working): updatedInput
            # MUST be nested inside decision, not at hookSpecificOutput
            # top level. Claude reads decision.updatedInput.
            print(json.dumps({
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "decision": {
                        "behavior": "allow",
                        "updatedInput": merged,
                    }
                }
            }, ensure_ascii=False), flush=True)

        def emit_cursor_permission(decision):
            # Cursor's IDE-internal sandbox dialog ignores hook stdout
            # decisions (verified empirically across multiple emit shapes).
            # SC's popup is a "通知 + 回到 Cursor" reminder, NOT an actual
            # decision pipeline — same model as Qoder. Emit a benign allow
            # JSON anyway so the hook chain completes cleanly without
            # blocking other entries (r2c, audit, etc.) and Cursor's own
            # default-allow timeout doesn't get tripped.
            print('{"decision":"allow"}', flush=True)

        def emit_cursor_question(decision, tool_input):
            # Cursor doesn't have a typed-question hook event today.
            # Match Claude's silent-on-non-answer behavior: stay quiet
            # so Cursor's built-in fallback runs.
            if not isinstance(decision, dict) or decision.get("decision") != "answer":
                return
            # Terminal injection path: same as Claude — stay silent when
            # the answer is being typed directly into the terminal.
            if decision.get("useTerminalInjection"):
                debug_log("cursor question: useTerminalInjection=true, staying silent")
                return
            # If Cursor ever surfaces an AskUserQuestion-style hook, the
            # answers shape will need to be confirmed against the
            # actual contract. For now, emit a generic allow with the
            # answers attached — best-effort.
            answers = decision.get("answers") or {}
            merged = dict(tool_input) if isinstance(tool_input, dict) else {}
            merged["answers"] = answers
            # Format from ping-island (verified working): updatedInput
            # MUST be nested inside decision, not at hookSpecificOutput
            # top level. Claude reads decision.updatedInput.
            print(json.dumps({
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "decision": {
                        "behavior": "allow",
                        "updatedInput": merged,
                    }
                }
            }, ensure_ascii=False), flush=True)

        DIALECTS = {
            "claude": {"permission": emit_claude_permission, "question": emit_claude_question},
            "qoder":  {"permission": emit_claude_permission, "question": emit_claude_question},
            "cursor": {"permission": emit_cursor_permission, "question": emit_cursor_question},
        }

        # --- Output helpers (format matches Ping Island exactly for claude) ---

        def _dialect(provider_id):
            return DIALECTS.get(provider_id) or DIALECTS["claude"]

        def print_allow(provider_id):
            # Fast-path emitter for allowlist matches and trusted-session
            # shortcuts — routes through the permission dialect so the
            # stdout shape matches whichever provider is wired.
            _dialect(provider_id)["permission"](None)

        def default_pass_through(is_question_event, provider_id):
            # Fired when the pending file disappears (Session Cove cancelled it)
            # or when we time out without a decision. Approval path -> emit allow
            # so the underlying tool keeps running. Question path -> stay silent;
            # Claude will fall back to its built-in terminal question prompt
            # rather than us injecting a guessed answer.
            dialect = _dialect(provider_id)
            if is_question_event:
                dialect["question"](None, None)
            else:
                dialect["permission"](None)

        def output_decision(decision, is_question_event=False, tool_input=None, provider_id="claude"):
            dialect = _dialect(provider_id)
            if is_question_event:
                dialect["question"](decision, tool_input)
            else:
                dialect["permission"](decision)

        # --- Fast-path checks ---

        def load_trusted_sessions():
            if not os.path.exists(SESSION_TRUST_PATH):
                return set()
            try:
                with open(SESSION_TRUST_PATH, "r", encoding="utf-8") as f:
                    return set(json.load(f).get("sessions", []))
            except Exception:
                return set()

        def match_allowlist(payload, provider_id):
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
                # v2 schema: rule.providerId scopes the match to one provider.
                # Pre-migration (v1) rules omit the field — default to "claude"
                # so they keep matching the legacy Claude path.
                if rule.get("providerId", "claude") != provider_id:
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

        def redact_tool_input(value):
            # Walk the structure replacing values under known-secret keys
            # with "<redacted>". Lists/scalars pass through as-is. The
            # check is case-insensitive substring against SECRET_KEY_PATTERNS.
            if isinstance(value, dict):
                out = {}
                for k, v in value.items():
                    lk = str(k).lower()
                    if any(p in lk for p in SECRET_KEY_PATTERNS):
                        out[k] = "<redacted>"
                    else:
                        out[k] = redact_tool_input(v)
                return out
            if isinstance(value, list):
                return [redact_tool_input(v) for v in value]
            return value

        def serialize_tool_input(tool_input):
            # Returns (text, truncated). text is None if serialization fails
            # entirely (caller skips writing the field).
            try:
                redacted = redact_tool_input(tool_input)
                text = json.dumps(redacted, ensure_ascii=False, indent=2, sort_keys=True)
            except Exception:
                return None, False
            encoded = text.encode("utf-8")
            if len(encoded) > TOOL_INPUT_SIZE_CAP:
                # Slice on byte boundary then drop any trailing partial code
                # point — Text view renders garbled glyphs otherwise.
                text = encoded[:TOOL_INPUT_SIZE_CAP].decode("utf-8", errors="ignore")
                return text, True
            return text, False

        def write_cursor_reminder(payload, provider_id, source_event):
            # Fire-and-forget reminder for Cursor's `before*` events when
            # the host is about to surface its own sandbox dialog. SC's
            # popup shows alongside Cursor's IDE dialog (kind=approval,
            # supportsExternalApproval=false → "回到 Cursor" focus button).
            # No response is read; SC's poll surfaces the popup and the
            # 1h staleness sweep cleans up orphans.
            ensure_dirs()
            session_id = str(payload.get("session_id") or "")
            cwd = str(payload.get("cwd") or os.getcwd())
            tool_input = payload.get("tool_input") or {}
            now = time.time()
            seed = "cursor-approval|{}|{}".format(session_id or "anon", now)
            request_id = "cursor-" + hashlib.sha256(seed.encode("utf-8")).hexdigest()[:16]
            request_path = os.path.join(PENDING, "{}.json".format(request_id))
            tool_label = {
                "beforeShellExecution": "Shell",
                "beforeMCPExecution": "MCP",
                "beforeReadFile": "ReadFile",
            }.get(source_event, "Cursor Tool")
            summary = stable_summary({"tool_name": tool_label, "tool_input": tool_input})
            match_value = extract_match_value({"tool_name": tool_label, "tool_input": tool_input})
            request = {
                "id": request_id,
                "schemaVersion": SCHEMA_VERSION,
                "providerId": provider_id,
                "kind": "approval",
                "sessionId": session_id,
                "toolName": tool_label,
                "projectPath": cwd,
                "summary": summary,
                "matchValue": match_value,
                "receivedAt": now,
            }
            serialized, truncated = serialize_tool_input(tool_input)
            if serialized is not None:
                request["toolInputJSON"] = serialized
                request["toolInputTruncated"] = truncated
            tmp = request_path + ".tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(request, f, ensure_ascii=False, indent=2, sort_keys=True)
            os.replace(tmp, request_path)

        def write_stop_request(payload, provider_id):
            # Stop hook is fire-and-forget: write the pending file, exit 0.
            # No response is ever read. Swift's poll loop surfaces the toast
            # and removes the file when the user dismisses it (or after the
            # 1h staleness sweep for orphans).
            ensure_dirs()
            session_id = str(payload.get("session_id") or "")
            cwd = str(payload.get("cwd") or os.getcwd())
            transcript = str(payload.get("transcript_path") or "")
            now = time.time()
            seed = "{}|{}".format(session_id or "anon", now)
            request_id = "stop-" + hashlib.sha256(seed.encode("utf-8")).hexdigest()[:16]
            request_path = os.path.join(PENDING, "{}.json".format(request_id))
            request = {
                "id": request_id,
                "schemaVersion": SCHEMA_VERSION,
                "providerId": provider_id,
                "kind": "completion",
                "sessionId": session_id,
                "toolName": "Stop",
                "projectPath": cwd,
                "summary": "Session 完成了一回合任务",
                "matchValue": "",
                "receivedAt": now,
                "completedAt": now,
                "transcriptPath": transcript,
            }
            tmp = request_path + ".tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(request, f, ensure_ascii=False, indent=2, sort_keys=True)
            os.replace(tmp, request_path)

        # --- Main ---

        def parse_provider_arg(argv):
            # Parse `--provider <id>` early. Anything else on the command
            # line is ignored — we don't accept positional args today.
            args = list(argv[1:])
            i = 0
            while i < len(args):
                if args[i] == "--provider" and i + 1 < len(args):
                    return args[i + 1]
                i += 1
            return "claude"

        def main():
            ensure_dirs()
            provider_id = parse_provider_arg(sys.argv)
            debug_log("INVOKED argv=" + " ".join(sys.argv) + " provider=" + provider_id)
            if provider_id not in DIALECTS:
                sys.stderr.write("[session-cove] unknown provider '{}', falling back to claude\\n".format(provider_id))
                provider_id = "claude"

            raw = sys.stdin.read()
            if not raw.strip():
                debug_log("empty stdin, exiting 0")
                return 0
            # Dump first 500 chars of raw stdin so we can see exactly what
            # the host (Cursor / Claude / Qoder) is feeding us.
            debug_log("STDIN: " + raw[:500].replace("\\n", " "))
            try:
                payload = json.loads(raw)
            except Exception as e:
                debug_log("JSON parse error: " + str(e))
                return 0

            event_name = payload.get("hook_event_name")
            debug_log("event=" + str(event_name) + " tool=" + str(payload.get("tool_name","")) + " session=" + str(payload.get("session_id",""))[:16])
            tool_name = str(payload.get("tool_name") or "")
            is_question_tool = tool_name in ("AskUserQuestion", "AskFollowupQuestion")
            # Cursor event mapping. `stop` becomes our Stop completion
            # toast; the `before*` family is approximated as "approval
            # required" by reading the payload's `tool_input.sandbox`
            # boolean, which Cursor sets only when the IDE intends to
            # surface its own sandbox dialog. Auto-allowed tool calls
            # (sandbox=false) get a silent allow without a popup so SC
            # doesn't fire on every routine tool invocation.
            if event_name == "stop":
                event_name = "Stop"
            elif event_name == "preToolUse":
                # Stale hooks.json entry from a previous SC version that
                # subscribed to preToolUse. Exit silently — preToolUse
                # `ask` is documented as not-enforced anyway, so even if
                # we tried to surface the dialog Cursor would ignore it.
                return 0
            elif event_name in ("beforeShellExecution", "beforeMCPExecution", "beforeReadFile"):
                cursor_tool_input = payload.get("tool_input") or {}
                will_surface_dialog = bool(cursor_tool_input.get("sandbox")) if isinstance(cursor_tool_input, dict) else False
                if will_surface_dialog:
                    # Cursor will pop its own sandbox dialog; mirror with
                    # an SC reminder + emit `permission: ask` so Cursor's
                    # dialog drives the actual decision. SC popup is a
                    # focus-button reminder, not a decision pipeline.
                    write_cursor_reminder(payload, provider_id, event_name)
                    print('{"permission":"ask"}', flush=True)
                else:
                    # Auto-allow path: don't surface SC; let Cursor proceed.
                    print('{"permission":"allow"}', flush=True)
                return 0
            # Three events feed Session Cove: legacy PermissionRequest
            # (yes/deny/always), PreToolUse for AskUserQuestion-style typed
            # answers, and Stop for "session finished a turn" toasts.
            is_question_event = event_name == "PreToolUse" and is_question_tool
            is_stop_event = event_name == "Stop"

            if is_stop_event:
                # Fire-and-forget: write completion request and exit 0
                # immediately. Stop hook contract has no `decision` stdout,
                # so blocking would stall every turn boundary.
                write_stop_request(payload, provider_id)
                return 0

            if event_name != "PermissionRequest" and not is_question_event:
                return 0

            # Snapshot the original tool_input so output_decision can echo
            # it back via updatedInput on the answer path. Helper functions
            # (match_allowlist / stable_summary / build_questions) each take
            # their own local copy from payload, so we keep this top-level
            # binding minimal and only used here.
            tool_input = payload.get("tool_input") or {}

            session_id = str(payload.get("session_id") or "")

            # Allowlist + trusted-session shortcuts only apply to the legacy
            # approval path. Question events always surface in the UI so the
            # user can answer; nothing to "pre-approve" for them.
            # Claude fires BOTH PreToolUse and PermissionRequest for question
            # tools (AskUserQuestion / AskFollowupQuestion). The PreToolUse
            # path writes a pending file and exits silently (fire-and-forget)
            # so Claude falls back to its terminal prompt. The PermissionRequest
            # path MUST emit allow — otherwise Claude blocks waiting for a
            # permission decision and the terminal prompt never renders.
            # Emitting allow here just means "yes you may ask the user a
            # question" — it does NOT bypass the actual Q&A flow.
            if is_question_tool and event_name == "PermissionRequest":
                debug_log("PermissionRequest for question tool — emit allow (unblock prompt rendering)")
                print_allow(provider_id)
                return 0

            if not is_question_event:
                if match_allowlist(payload, provider_id):
                    print_allow(provider_id)
                    return 0
                if session_id and session_id in load_trusted_sessions():
                    print_allow(provider_id)
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
                "providerId": provider_id,
                "sessionId": session_id,
                "toolName": tool_name or "Tool",
                "projectPath": str(payload.get("cwd") or os.getcwd()),
                "summary": stable_summary(payload),
                "matchValue": extract_match_value(payload),
                "receivedAt": time.time(),
                "schemaVersion": SCHEMA_VERSION,
            }
            if is_question_event:
                request.update({
                    "kind": "question",
                    "expectsAnswer": True,
                    "questions": build_questions(payload),
                })
            else:
                # Approval path: ship the raw tool_input (redacted, capped)
                # so the chevron / expanded detail panel can render the full
                # bash command, write content, edit diff, etc. Question
                # path skips this — its tool_input is already surfaced as
                # questions[] and re-emitting it would risk leaking values
                # the user typed in a prior round.
                serialized, truncated = serialize_tool_input(tool_input)
                if serialized is not None:
                    request["toolInputJSON"] = serialized
                    request["toolInputTruncated"] = truncated

            tmp = request_path + ".tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(request, f, ensure_ascii=False, indent=2, sort_keys=True)
            os.replace(tmp, request_path)

            # Question events now BLOCK just like approval events — Python
            # writes the pending file, polls for SC's response, then emits
            # updatedInput to Claude's stdout. This is the ONLY reliable
            # path: Claude ignores terminal stdin for AskUserQuestion and
            # treats silent-exit as "user skipped the question". The old
            # fire-and-forget approach (exit 0 → terminal prompt) was
            # disproven: Claude skips the question entirely when hook is
            # silent, never renders a terminal prompt at all.
            #
            # For managed sessions (SC owns the pty), the answers still
            # flow through this same hook stdout path — SC writes the
            # response file, Python emits updatedInput, Claude continues.
            # The pty master fd is only used as a FALLBACK if this path
            # somehow fails (future consideration).

            deadline = time.time() + TIMEOUT_SECONDS
            last_touch = time.time()
            while time.time() < deadline:
                if os.path.exists(response_path):
                    with open(response_path, "r", encoding="utf-8") as f:
                        decision = json.load(f)
                    output_decision(decision, is_question_event=is_question_event, tool_input=tool_input, provider_id=provider_id)
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
                    # Race: Swift writes response first, then removes pending.
                    # If we observed `response_path` missing on this loop's
                    # first check, then Swift completed both writes before our
                    # second check, we'd miss the answer entirely and emit
                    # `default_pass_through` (silent). Re-read response one
                    # more time before giving up. This is the difference
                    # between "user submitted but Claude saw no answer" and
                    # the real timeout case.
                    if os.path.exists(response_path):
                        with open(response_path, "r", encoding="utf-8") as f:
                            decision = json.load(f)
                        output_decision(decision, is_question_event=is_question_event, tool_input=tool_input, provider_id=provider_id)
                        try:
                            os.remove(response_path)
                        except OSError:
                            pass
                        return 0
                    default_pass_through(is_question_event, provider_id)
                    return 0
                # Refresh mtime every 30s so the Swift-side stale-file
                # sweeper (24 h cutoff) doesn't reclaim a real pending
                # while the user is still reading session context. Cheap
                # syscall; only happens while we're polling.
                now = time.time()
                if now - last_touch > 30:
                    try:
                        os.utime(request_path, None)
                    except OSError:
                        pass
                    last_touch = now
                time.sleep(0.2)
            default_pass_through(is_question_event, provider_id)
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
