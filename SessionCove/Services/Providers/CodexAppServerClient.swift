import Foundation

/// Session Cove's client for the **Codex app-server** (Codex 0.143+).
///
/// Unlike the Claude/Codex *hook* path (`ClaudePermissionHook` +
/// `HookSocketServer`), which only carries per-request allow/deny verdicts,
/// the app-server exposes Codex's full interactive protocol over a local
/// WebSocket + JSON-RPC 2.0 channel:
///
///   * `item/commandExecution/requestApproval`  — command approval
///   * `item/fileChange/requestApproval`        — file-change approval
///   * `item/permissions/requestApproval`       — permission-grant approval
///   * `item/tool/requestUserInput`             — **interactive questions**
///
/// Approvals accept `accept` / `acceptForSession` / `decline` / `cancel`
/// (so "始终允许" == `acceptForSession` IS available here — the hook path
/// could not express it). Questions are answered with a
/// `{answers: {questionId: {answers: [...]}}}` map.
///
/// ## Integration strategy — reuse the existing pending/response queue
/// Rather than build a parallel UI, this client **writes the same pending
/// JSON files** that `CoveViewModel.hookPollTask` already consumes, so
/// approvals and questions surface through the existing `PermissionPingCard`
/// / `HookQuestionView`. It then **watches the responses directory**; when SC
/// writes the user's decision file, the client maps it back to the correct
/// app-server WebSocket reply and resolves the request.
///
/// The bridge between "SC's decision vocabulary" (`allow` / `allowSession` /
/// `deny` / `answer`) and "Codex's wire vocabulary" (`accept` /
/// `acceptForSession` / `decline` / answers-map) lives in `sendDecision`.
///
/// Protocol confirmed against the official schema emitted by
/// `codex app-server generate-json-schema` on Codex 0.143.0 (see
/// `/tmp/codex-schema/ServerRequest.json` et al).
actor CodexAppServerClient {
    static let shared = CodexAppServerClient()

    /// Port for the local app-server. Deliberately NOT 41241 (ping-island's
    /// port) to avoid colliding with any stray instance; SC owns this one.
    private let port = 42477
    private static let maxMessageSize = 32 * 1024 * 1024

    private var process: Process?
    private var websocket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var responseWatchTask: Task<Void, Never>?
    private var requestSequence = 0
    private var started = false

    /// Kind of a pending server→client request, so the response watcher knows
    /// how to translate SC's decision into the right app-server reply.
    private enum PendingKind {
        case commandApproval
        case fileApproval
        case permissionsApproval
        case userInput(questionIds: [String])
    }

    private struct PendingServerRequest {
        let jsonrpcId: String        // the app-server request id we must reply to
        let threadId: String
        let kind: PendingKind
        let requestedPermissions: [String: Any]?
    }

    /// requestId (== the pending-file id we write) → server request context.
    private var pending: [String: PendingServerRequest] = [:]

    /// jsonrpc id → continuation for client→server requests (initialize, etc).
    private var pendingResponses: [String: CheckedContinuation<[String: Any], Error>] = [:]

    private init() {}

    // MARK: - Lifecycle

    /// Start the app-server (if needed) and connect. Idempotent.
    func start() async {
        guard !started else { return }
        started = true

        if await connect() {
            startResponseWatcher()
            return
        }

        guard let executable = resolveCodexExecutable() else {
            log("Codex CLI not found; app-server client disabled")
            started = false
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = ["app-server", "--listen", "ws://127.0.0.1:\(port)"]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        do {
            try proc.run()
            self.process = proc
            log("launched codex app-server pid=\(proc.processIdentifier) port=\(port)")
        } catch {
            log("failed to launch codex app-server: \(error.localizedDescription)")
            started = false
            return
        }

        // Wait up to 3s for it to accept connections.
        for _ in 0..<12 {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if await connect() {
                startResponseWatcher()
                return
            }
        }
        log("unable to connect to codex app-server on port \(port)")
        started = false
    }

    func stop() {
        receiveTask?.cancel(); receiveTask = nil
        responseWatchTask?.cancel(); responseWatchTask = nil
        websocket?.cancel(with: .goingAway, reason: nil); websocket = nil
        process?.terminate(); process = nil
        started = false
        for (_, c) in pendingResponses { c.resume(throwing: CancellationError()) }
        pendingResponses.removeAll()
        pending.removeAll()
    }

    // MARK: - Connection

    private func connect() async -> Bool {
        guard websocket == nil else { return true }
        guard let url = URL(string: "ws://127.0.0.1:\(port)") else { return false }

        let task = URLSession.shared.webSocketTask(with: url)
        task.maximumMessageSize = Self.maxMessageSize
        task.resume()
        self.websocket = task

        receiveTask = Task { [weak self] in await self?.receiveLoop() }

        do {
            _ = try await sendRequest(method: "initialize", params: [
                "clientInfo": [
                    "name": "SessionCove",
                    "title": "Session Cove",
                    "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
                ],
                "capabilities": ["experimentalApi": true]
            ])
            log("app-server initialized")
            return true
        } catch {
            log("initialize failed: \(error.localizedDescription)")
            receiveTask?.cancel(); receiveTask = nil
            task.cancel(with: .goingAway, reason: nil)
            self.websocket = nil
            return false
        }
    }

    private func receiveLoop() async {
        while !Task.isCancelled {
            guard let websocket else { return }
            do {
                let message = try await websocket.receive()
                await handle(message)
            } catch {
                log("websocket closed: \(error.localizedDescription)")
                break
            }
        }
        websocket?.cancel(with: .goingAway, reason: nil)
        websocket = nil
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) async {
        let data: Data
        switch message {
        case .data(let raw): data = raw
        case .string(let text): data = Data(text.utf8)
        @unknown default: return
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        // Server-initiated request (has method + id) vs notification (method,
        // no id) vs a response to one of our requests (id + result/error).
        if let method = json["method"] as? String {
            if let idValue = json["id"], !(idValue is NSNull) {
                await handleServerRequest(id: stringify(idValue), method: method,
                                          params: json["params"] as? [String: Any] ?? [:])
            }
            // Notifications (thread/status/changed, etc) are ignored for now —
            // approvals/questions are all server *requests*, handled above.
            return
        }

        guard let idValue = json["id"] else { return }
        let id = stringify(idValue)
        guard let continuation = pendingResponses.removeValue(forKey: id) else { return }
        if let result = json["result"] as? [String: Any] {
            continuation.resume(returning: result)
        } else if json["result"] is NSNull {
            continuation.resume(returning: [:])
        } else if let err = json["error"] as? [String: Any] {
            let msg = (err["message"] as? String) ?? "Unknown app-server error"
            continuation.resume(throwing: NSError(domain: "CodexAppServer", code: 1,
                userInfo: [NSLocalizedDescriptionKey: msg]))
        } else {
            continuation.resume(returning: [:])
        }
    }

    // MARK: - Server → client requests (approvals + questions)

    private func handleServerRequest(id: String, method: String, params: [String: Any]) async {
        switch method {
        case "item/commandExecution/requestApproval":
            let threadId = (params["threadId"] as? String) ?? (params["conversationId"] as? String) ?? ""
            guard !threadId.isEmpty else { await replyRaw(id: id, result: ["decision": "decline"]); return }
            let command = ((params["command"] as? [String]) ?? []).joined(separator: " ")
            let cwd = params["cwd"] as? String ?? ""
            let reason = params["reason"] as? String
            enqueueApproval(
                jsonrpcId: id, threadId: threadId, kind: .commandApproval,
                toolName: "exec_command",
                summary: reason ?? (command.isEmpty ? "Codex wants to run a terminal command." : command),
                matchValue: command,
                cwd: cwd,
                toolInput: params["command"].map { ["command": $0, "cwd": cwd] } ?? ["cwd": cwd],
                requestedPermissions: nil
            )

        case "item/fileChange/requestApproval":
            guard let threadId = params["threadId"] as? String else { await replyRaw(id: id, result: ["decision": "decline"]); return }
            let reason = params["reason"] as? String
            let grantRoot = params["grantRoot"] as? String
            enqueueApproval(
                jsonrpcId: id, threadId: threadId, kind: .fileApproval,
                toolName: "file_change",
                summary: reason ?? grantRoot ?? "Codex wants to modify files in this workspace.",
                matchValue: grantRoot ?? "",
                cwd: grantRoot ?? "",
                toolInput: ["grantRoot": grantRoot ?? "", "reason": reason ?? ""],
                requestedPermissions: nil
            )

        case "item/permissions/requestApproval":
            guard let threadId = params["threadId"] as? String else { await replyRaw(id: id, result: ["permissions": [:], "scope": "turn"]); return }
            let permissions = params["permissions"] as? [String: Any] ?? [:]
            let reason = params["reason"] as? String
            enqueueApproval(
                jsonrpcId: id, threadId: threadId, kind: .permissionsApproval,
                toolName: "permissions_request",
                summary: reason ?? "Codex is requesting additional permissions.",
                matchValue: "",
                cwd: "",
                toolInput: permissions,
                requestedPermissions: permissions
            )

        case "item/tool/requestUserInput":
            guard let threadId = params["threadId"] as? String else { await replyRaw(id: id, result: ["answers": [:]]); return }
            let rawQuestions = params["questions"] as? [[String: Any]] ?? []
            let questions = Self.parseQuestions(rawQuestions)
            enqueueQuestion(jsonrpcId: id, threadId: threadId, questions: questions,
                            cwd: params["cwd"] as? String ?? "")

        default:
            // Unknown server request — reply with an empty result so the
            // app-server doesn't hang. (mcpServer/elicitation, dynamic tool
            // calls, attestation, etc. are out of scope for Phase 2.)
            await replyRaw(id: id, result: [:])
        }
    }

    /// Build & write the shared pending file for an approval.
    private func enqueueApproval(
        jsonrpcId: String, threadId: String, kind: PendingKind,
        toolName: String, summary: String, matchValue: String, cwd: String,
        toolInput: [String: Any], requestedPermissions: [String: Any]?
    ) {
        let requestId = "codex-\(threadId)-\(jsonrpcId)"
        pending[requestId] = PendingServerRequest(
            jsonrpcId: jsonrpcId, threadId: threadId, kind: kind,
            requestedPermissions: requestedPermissions
        )
        var data: [String: Any] = [
            "id": requestId,
            "providerId": "codex",
            "sessionId": threadId,
            "toolName": toolName,
            "projectPath": cwd,
            "summary": summary,
            "matchValue": matchValue,
            "receivedAt": Date().timeIntervalSince1970,
            "schemaVersion": 4,
            "kind": "approval",
        ]
        if let jsonData = try? JSONSerialization.data(withJSONObject: toolInput, options: [.prettyPrinted, .sortedKeys]),
           let jsonStr = String(data: jsonData, encoding: .utf8) {
            data["toolInputJSON"] = String(jsonStr.prefix(8192))
            data["toolInputTruncated"] = jsonStr.count > 8192
        }
        writePending(requestId: requestId, data: data)
    }

    /// Build & write the shared pending file for an interactive question.
    private func enqueueQuestion(jsonrpcId: String, threadId: String,
                                 questions: [[String: Any]], cwd: String) {
        let requestId = "codex-\(threadId)-\(jsonrpcId)"
        let questionIds = questions.compactMap { $0["id"] as? String }
        pending[requestId] = PendingServerRequest(
            jsonrpcId: jsonrpcId, threadId: threadId,
            kind: .userInput(questionIds: questionIds), requestedPermissions: nil
        )
        let prompt = (questions.first?["prompt"] as? String) ?? "Codex needs your input."
        let data: [String: Any] = [
            "id": requestId,
            "providerId": "codex",
            "sessionId": threadId,
            "toolName": "AskUserQuestion",
            "projectPath": cwd,
            "summary": prompt,
            "matchValue": "",
            "receivedAt": Date().timeIntervalSince1970,
            "schemaVersion": 4,
            "kind": "question",
            "questions": questions,
        ]
        writePending(requestId: requestId, data: data)
    }

    private func writePending(requestId: String, data: [String: Any]) {
        let dir = ClaudePermissionHook.sharedPendingDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("\(requestId).json")
        if let d = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]) {
            try? d.write(to: path, options: .atomic)
            log("wrote pending \(requestId)")
        }
    }

    // MARK: - Response watcher (SC decision → app-server reply)

    private func startResponseWatcher() {
        guard responseWatchTask == nil else { return }
        responseWatchTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.drainResponses()
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    /// Poll the shared responses dir for decisions on our pending Codex
    /// requests and translate them into app-server WebSocket replies.
    private func drainResponses() async {
        guard !pending.isEmpty else { return }
        let dir = ClaudePermissionHook.sharedResponseDirectory
        for (requestId, ctx) in pending {
            let path = dir.appendingPathComponent("\(requestId).json")
            guard FileManager.default.fileExists(atPath: path.path),
                  let raw = try? Data(contentsOf: path),
                  let decision = try? JSONSerialization.jsonObject(with: raw) as? [String: Any]
            else { continue }

            let key = (decision["decision"] as? String) ?? "deny"
            await sendDecision(ctx: ctx, decisionKey: key, decision: decision)

            pending.removeValue(forKey: requestId)
            try? FileManager.default.removeItem(at: path)
            try? FileManager.default.removeItem(
                at: ClaudePermissionHook.sharedPendingDirectory.appendingPathComponent("\(requestId).json"))
        }
    }

    /// Map SC's decision vocabulary onto the Codex app-server wire reply.
    ///
    ///   SC `allow`        → `accept`
    ///   SC `allowSession` → `acceptForSession`   (== 始终允许 for Codex)
    ///   SC `alwaysAllow`  → `acceptForSession`   (defensive; card hides it,
    ///                        but map it sanely if it ever appears)
    ///   SC `deny`         → `decline`
    ///   SC `answer`       → answers map (userInput only)
    private func sendDecision(ctx: PendingServerRequest, decisionKey: String, decision: [String: Any]) async {
        switch ctx.kind {
        case .commandApproval, .fileApproval:
            let wire: String
            switch decisionKey {
            case "allow": wire = "accept"
            case "allowSession", "alwaysAllow": wire = "acceptForSession"
            default: wire = "decline"
            }
            await replyRaw(id: ctx.jsonrpcId, result: ["decision": wire])

        case .permissionsApproval:
            let grant = (decisionKey == "deny")
            await replyRaw(id: ctx.jsonrpcId, result: [
                "permissions": grant ? [:] : (ctx.requestedPermissions ?? [:]),
                "scope": (decisionKey == "allowSession" || decisionKey == "alwaysAllow") ? "session" : "turn"
            ])

        case .userInput(let questionIds):
            // Denying a question: reply with empty answers so Codex proceeds.
            var answersOut: [String: Any] = [:]
            if decisionKey == "answer", let answers = decision["answers"] as? [String: String] {
                // SC stores {questionId: "comma,joined,labels"}; app-server
                // wants {questionId: {answers: [label, ...]}}.
                for qid in questionIds {
                    let raw = answers[qid] ?? ""
                    let parts = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    answersOut[qid] = ["answers": parts.isEmpty ? [raw] : parts]
                }
            }
            await replyRaw(id: ctx.jsonrpcId, result: ["answers": answersOut])
        }
    }

    // MARK: - JSON-RPC plumbing

    @discardableResult
    private func sendRequest(method: String, params: [String: Any]) async throws -> [String: Any] {
        guard let websocket else {
            throw NSError(domain: "CodexAppServer", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Websocket not connected"])
        }
        requestSequence += 1
        let id = String(requestSequence)
        let payload: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method, "params": params]
        let text = try Self.encode(payload)
        return try await withCheckedThrowingContinuation { continuation in
            pendingResponses[id] = continuation
            Task {
                do { try await websocket.send(.string(text)) }
                catch {
                    if let c = pendingResponses.removeValue(forKey: id) { c.resume(throwing: error) }
                }
            }
        }
    }

    private func replyRaw(id: String, result: [String: Any]) async {
        guard let websocket else { return }
        let payload: [String: Any] = ["jsonrpc": "2.0", "id": id, "result": result]
        guard let text = try? Self.encode(payload) else { return }
        do { try await websocket.send(.string(text)) }
        catch { log("failed to send reply: \(error.localizedDescription)") }
    }

    // MARK: - Helpers

    private static func encode(_ obj: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
        guard let s = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "CodexAppServer", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "encode failed"])
        }
        return s
    }

    private nonisolated func stringify(_ value: Any) -> String {
        if let s = value as? String { return s }
        if let i = value as? Int { return String(i) }
        if let d = value as? Double { return String(Int(d)) }
        return "\(value)"
    }

    /// Parse app-server questions into the SC pending-file question schema
    /// (matches `ClaudePermissionHook.decodeQuestion`).
    nonisolated static func parseQuestions(_ raw: [[String: Any]]) -> [[String: Any]] {
        raw.map { q in
            let options = (q["options"] as? [[String: Any]] ?? []).enumerated().map { idx, opt -> [String: Any] in
                let label = opt["label"] as? String ?? "Option \(idx + 1)"
                return ["id": label, "title": label, "detail": opt["description"] as? String as Any]
            }
            return [
                "id": q["id"] as? String ?? UUID().uuidString,
                "header": q["header"] as? String ?? "Question",
                "prompt": q["question"] as? String ?? "",
                "detail": NSNull(),
                "options": options,
                "allowsMultiple": (q["isMultiple"] as? Bool) ?? (q["allowsMultiple"] as? Bool) ?? false,
                "allowsOther": (q["isOther"] as? Bool) ?? true,
                "isSecret": q["isSecret"] as? Bool ?? false,
            ]
        }
    }

    private func resolveCodexExecutable() -> String? {
        let candidates = [
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
            "\(NSHomeDirectory())/.npm-global/bin/codex",
            "\(NSHomeDirectory())/.local/bin/codex",
        ]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) { return c }
        // PATH fallback via `which`.
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        which.arguments = ["which", "codex"]
        let pipe = Pipe(); which.standardOutput = pipe
        try? which.run(); which.waitUntilExit()
        if let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !out.isEmpty,
           FileManager.default.isExecutableFile(atPath: out) {
            return out
        }
        return nil
    }

    private nonisolated func log(_ msg: String) {
        NSLog("[CodexAppServer] \(msg)")
    }
}
