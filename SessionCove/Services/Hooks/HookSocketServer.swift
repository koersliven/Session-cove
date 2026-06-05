import Foundation

/// Unix socket server that receives hook requests from the Python bridge
/// and returns decisions (answers/approvals) synchronously. Replaces the
/// file-poll mechanism. Modeled after Ping Island's /tmp/island.sock.
///
/// Flow:
///   Python bridge connects → sends JSON payload (newline-terminated)
///   → server reads → dispatches to HookRequestHandler
///   → handler shows UI / auto-resolves → returns decision JSON
///   → server writes decision back on same connection → bridge reads → emits stdout
///
/// Multiple bridge processes connect independently (PreToolUse + PermissionRequest
/// for the same AskUserQuestion). The handler deduplicates by tool_input hash and
/// returns the SAME answer to both connections.
@MainActor
final class HookSocketServer {
    static let shared = HookSocketServer()
    static let socketPath = "/tmp/session-cove.sock"

    private var serverFD: Int32 = -1
    private var isRunning = false
    private var acceptThread: Thread?

    /// Callback invoked on MainActor when a hook request arrives that needs
    /// user interaction (question/approval popup). Returns the decision JSON
    /// to send back to the bridge.
    var onRequest: ((HookSocketRequest) async -> HookSocketResponse)?

    /// Pending question dedup: when the first connection for a question arrives,
    /// we store a continuation. When the second arrives (same dedup key), we
    /// wait for the first's answer and return the same response.
    private var pendingQuestions: [String: PendingQuestion] = [:]

    struct PendingQuestion {
        let continuations: [CheckedContinuation<HookSocketResponse, Never>]
        var response: HookSocketResponse?
    }

    func start() {
        guard !isRunning else { return }

        // Remove stale socket
        unlink(Self.socketPath)

        // Create socket
        serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else {
            print("[HookSocketServer] socket() failed: \(errno)")
            return
        }

        // Bind
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Self.socketPath.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let bound = ptr.withMemoryRebound(to: CChar.self, capacity: Int(104)) { dest in
                pathBytes.withUnsafeBufferPointer { src in
                    let count = min(src.count, 104)
                    dest.update(from: src.baseAddress!, count: count)
                    return count
                }
            }
            _ = bound
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(serverFD, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            print("[HookSocketServer] bind() failed: \(errno)")
            close(serverFD)
            serverFD = -1
            return
        }

        // Listen
        guard listen(serverFD, 10) == 0 else {
            print("[HookSocketServer] listen() failed: \(errno)")
            close(serverFD)
            serverFD = -1
            return
        }

        isRunning = true
        print("[HookSocketServer] listening on \(Self.socketPath)")

        // Accept loop on background thread
        let fd = serverFD
        Thread.detachNewThread {
            while true {
                var clientAddr = sockaddr_un()
                var clientLen = socklen_t(MemoryLayout<sockaddr_un>.size)
                let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                        accept(fd, sockPtr, &clientLen)
                    }
                }
                if clientFD < 0 {
                    if errno == EBADF { break } // server shut down
                    continue
                }
                // Handle each connection in its own thread
                Thread.detachNewThread { [weak self] in
                    self?.handleConnection(clientFD)
                }
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        close(serverFD)
        serverFD = -1
        unlink(Self.socketPath)
    }

    // MARK: - Connection handling

    private nonisolated func handleConnection(_ fd: Int32) {
        defer { close(fd) }

        // Read until newline (JSON payload is single-line)
        var buffer = Data()
        var byte: UInt8 = 0
        while true {
            let n = read(fd, &byte, 1)
            if n <= 0 { return }
            if byte == 0x0A { break } // newline = end of request
            buffer.append(byte)
        }

        guard let payload = try? JSONSerialization.jsonObject(with: buffer) as? [String: Any] else {
            let empty = "{}\n".data(using: .utf8)!
            _ = empty.withUnsafeBytes { write(fd, $0.baseAddress!, $0.count) }
            return
        }

        let request = HookSocketRequest(payload: payload)
        let eventName = request.eventName
        let toolName = request.toolName
        let isQuestionTool = (toolName == "AskUserQuestion" || toolName == "AskFollowupQuestion")

        // Stop: fire-and-forget — write pending for completion toast, no blocking
        if eventName == "Stop" {
            writeStopPending(request: request)
            let empty = "{}\n".data(using: .utf8)!
            _ = empty.withUnsafeBytes { write(fd, $0.baseAddress!, $0.count) }
            return
        }

        // ALL other events (PermissionRequest, PreToolUse):
        // Write pending file → SC's hookPollTask picks it up → shows popup →
        // user decides → SC writes response file → we read it → return to bridge.
        // This is the SAME mechanism as the old Python file-poll bridge, just
        // with socket as the transport instead of direct stdout. The critical
        // difference: for question tools, BOTH PreToolUse and PermissionRequest
        // hooks get the SAME answer (via dedup key) because the socket server
        // can serve multiple connections from the same pending/response pair.
        let response = handleHookEvent(request: request)

        if let data = response.jsonData {
            let withNewline = data + Data([0x0A])
            _ = withNewline.withUnsafeBytes { write(fd, $0.baseAddress!, $0.count) }
        }
    }

    private func handleRequest(_ request: HookSocketRequest) -> HookSocketResponse {
        let eventName = request.eventName
        let toolName = request.toolName
        let isQuestionTool = (toolName == "AskUserQuestion" || toolName == "AskFollowupQuestion")

        // For non-question PermissionRequest: auto-allow (same as before)
        if eventName == "PermissionRequest" && !isQuestionTool {
            // Check allowlist / trusted session
            if let sessionId = request.sessionId, !sessionId.isEmpty,
               ClaudePermissionHook.isSessionTrusted(sessionId) {
                return .allow(eventName: eventName)
            }
            // Otherwise surface as approval popup — but for now auto-allow
            // (the file-based approval flow still works for this)
            return .allow(eventName: eventName)
        }

        // Stop event: fire-and-forget notification
        if eventName == "Stop" {
            return .empty
        }

        // Question tool (PreToolUse or PermissionRequest):
        // Dedup by tool_input hash — if another connection already asked
        // for the same question, wait for that answer.
        let dedupKey = request.dedupKey

        if let pending = pendingQuestions[dedupKey], let resp = pending.response {
            // Answer already available from the other hook's connection
            return resp
        }

        // First connection for this question — trigger UI
        // For now: create the pending entry, trigger the popup synchronously
        // In a real async implementation we'd use continuations.
        // HACK: synchronous dispatch since we're already on main thread.
        let response = triggerQuestionUI(request: request)

        // Cache for the second connection
        pendingQuestions[dedupKey] = PendingQuestion(continuations: [], response: response)

        // Clear after 30s (so stale entries don't accumulate)
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            self?.pendingQuestions.removeValue(forKey: dedupKey)
        }

        return response
    }

    /// Write a Stop pending file (fire-and-forget, for completion toast).
    private nonisolated func writeStopPending(request: HookSocketRequest) {
        let pendingDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".session-cove/hooks/pending", isDirectory: true)
        let sessionId = request.sessionId ?? ""
        let cwd = request.payload["cwd"] as? String ?? ""
        let now = Date().timeIntervalSince1970
        let seed = "\(sessionId)|\(now)"
        var h: UInt64 = 5381
        for byte in seed.utf8 { h = h &* 33 &+ UInt64(byte) }
        let requestId = "stop-" + String(format: "%016llx", h).suffix(16)

        let pending: [String: Any] = [
            "id": requestId,
            "schemaVersion": 4,
            "providerId": "claude",
            "kind": "completion",
            "sessionId": sessionId,
            "toolName": "Stop",
            "projectPath": cwd,
            "summary": "Session 完成了一回合任务",
            "matchValue": "",
            "receivedAt": now,
            "completedAt": now,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: pending, options: [.prettyPrinted, .sortedKeys]) {
            let path = pendingDir.appendingPathComponent("\(requestId).json")
            try? data.write(to: path, options: .atomic)
        }
    }

    /// Handle any hook event: write pending, poll for response, return decision.
    /// Runs on a BACKGROUND THREAD (never main) so SC's hookPollTask on
    /// MainActor can pick up the pending, show UI, write response.
    private nonisolated func handleHookEvent(request: HookSocketRequest) -> HookSocketResponse {
        let eventName = request.eventName
        let toolName = request.toolName
        let isQuestionTool = (toolName == "AskUserQuestion" || toolName == "AskFollowupQuestion")

        let pendingDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".session-cove/hooks/pending", isDirectory: true)
        let responseDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".session-cove/hooks/responses", isDirectory: true)

        let toolInput = request.payload["tool_input"] as? [String: Any] ?? [:]
        let sessionId = request.sessionId ?? ""
        let cwd = request.payload["cwd"] as? String ?? ""

        // Build request_id WITHOUT event_name so PreToolUse and PermissionRequest
        // for the same AskUserQuestion share the SAME pending/response file.
        // Both bridge processes poll the same ID, both see the same answer,
        // and SC only shows ONE popup (first pending wins; second = duplicate id → skip).
        let stable: [String: Any] = [
            "tool_name": toolName,
            "tool_input": toolInput,
            "cwd": cwd
        ]
        let seed = (try? JSONSerialization.data(withJSONObject: stable, options: .sortedKeys))
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        var h: UInt64 = 5381
        for byte in seed.utf8 { h = h &* 33 &+ UInt64(byte) }
        let requestId = String(format: "%016llx", h)

        let pendingPath = pendingDir.appendingPathComponent("\(requestId).json")
        let responsePath = responseDir.appendingPathComponent("\(requestId).json")

        // Remove stale response
        try? FileManager.default.removeItem(at: responsePath)

        // Build pending file
        var pendingData: [String: Any] = [
            "id": requestId,
            "providerId": "claude",
            "sessionId": sessionId,
            "toolName": toolName,
            "projectPath": cwd,
            "summary": buildSummary(toolName: toolName, toolInput: toolInput),
            "matchValue": extractMatchValue(toolName: toolName, toolInput: toolInput),
            "receivedAt": Date().timeIntervalSince1970,
            "schemaVersion": 4,
        ]

        if isQuestionTool {
            pendingData["kind"] = "question"
            pendingData["questions"] = buildQuestions(toolInput: toolInput)
        } else {
            pendingData["kind"] = "approval"
            // Serialize tool_input for the detail panel
            if let jsonData = try? JSONSerialization.data(withJSONObject: toolInput, options: [.prettyPrinted, .sortedKeys]),
               let jsonStr = String(data: jsonData, encoding: .utf8) {
                let capped = jsonStr.prefix(8192)
                pendingData["toolInputJSON"] = String(capped)
                pendingData["toolInputTruncated"] = jsonStr.count > 8192
            }
        }

        // Write pending atomically
        if let data = try? JSONSerialization.data(withJSONObject: pendingData, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: pendingPath, options: .atomic)
        }

        // Poll for response (blocking on this background thread)
        let deadline = Date().addingTimeInterval(86400)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: responsePath.path) {
                if let data = try? Data(contentsOf: responsePath),
                   let decision = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

                    // DON'T delete files — the OTHER bridge process
                    // (PreToolUse/PermissionRequest for same question)
                    // shares the same pending/response pair and needs
                    // to read the same answer. SC's TTL sweep handles
                    // cleanup.

                    let decisionValue = decision["decision"] as? String ?? "allow"

                    if isQuestionTool && decisionValue == "answer" {
                        let answers = decision["answers"] as? [String: String] ?? [:]
                        var merged = toolInput
                        merged["answers"] = answers
                        return .updatedInput(eventName: eventName, input: merged)
                    } else if decisionValue == "deny" {
                        return .deny(eventName: eventName)
                    } else {
                        return .allow(eventName: eventName)
                    }
                }
            }
            // Pending gone but response might exist (written by SC after
            // user answered — the other bridge process may have already
            // polled it). Re-check response before falling back.
            if !FileManager.default.fileExists(atPath: pendingPath.path) {
                if FileManager.default.fileExists(atPath: responsePath.path),
                   let data = try? Data(contentsOf: responsePath),
                   let decision = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let decisionValue = decision["decision"] as? String ?? "allow"
                    if isQuestionTool && decisionValue == "answer" {
                        let answers = decision["answers"] as? [String: String] ?? [:]
                        var merged = toolInput
                        merged["answers"] = answers
                        return .updatedInput(eventName: eventName, input: merged)
                    }
                    return decisionValue == "deny"
                        ? .deny(eventName: eventName)
                        : .allow(eventName: eventName)
                }
                return .allow(eventName: eventName)
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return .allow(eventName: eventName)
    }

    private nonisolated func buildSummary(toolName: String, toolInput: [String: Any]) -> String {
        if let cmd = toolInput["command"] as? String { return "\(toolName): \(String(cmd.prefix(220)))" }
        if let path = toolInput["file_path"] as? String { return "\(toolName): \(String(path.prefix(220)))" }
        if let desc = toolInput["description"] as? String { return "\(toolName): \(String(desc.prefix(220)))" }
        return "\(toolName) is asking for permission."
    }

    private nonisolated func extractMatchValue(toolName: String, toolInput: [String: Any]) -> String {
        if toolName == "Bash" { return toolInput["command"] as? String ?? "" }
        if ["Read","Write","Edit","MultiEdit"].contains(toolName) {
            return toolInput["file_path"] as? String ?? toolInput["path"] as? String ?? ""
        }
        return ""
    }

    private nonisolated func buildQuestions(toolInput: [String: Any]) -> [[String: Any]] {
        let questions = toolInput["questions"] as? [[String: Any]] ?? []
        return questions.enumerated().map { (idx, q) in
            let opts = (q["options"] as? [[String: Any]])?.enumerated().map { (oi, opt) -> [String: Any] in
                ["id": "q\(idx+1)-o\(oi+1)",
                 "title": opt["label"] as? String ?? "",
                 "detail": (opt["description"] as? String) as Any]
            } ?? []
            return [
                "id": "q\(idx+1)",
                "header": q["header"] as? String ?? "",
                "prompt": q["question"] as? String ?? "",
                "options": opts,
                "isMultiple": q["multiSelect"] as? Bool ?? false,
                "isOther": false,
                "isSecret": false
            ] as [String: Any]
        }
    }

    private nonisolated func triggerQuestionUI(request: HookSocketRequest) -> HookSocketResponse {
        // Build the updatedInput response (same format as Ping Island)
        // For now: this needs to integrate with CoveViewModel's question popup.
        // TEMPORARY: write a pending file so existing SC popup mechanism works,
        // then poll for the response file.
        // TODO: Replace with direct CoveViewModel integration.

        let toolInput = request.payload["tool_input"] as? [String: Any] ?? [:]
        let questions = toolInput["questions"] as? [[String: Any]] ?? []

        // Write pending file for SC's existing popup mechanism
        let pendingDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".session-cove/hooks/pending", isDirectory: true)
        let responseDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".session-cove/hooks/responses", isDirectory: true)

        let requestId = request.dedupKey
        let pendingPath = pendingDir.appendingPathComponent("\(requestId).json")
        let responsePath = responseDir.appendingPathComponent("\(requestId).json")

        // Build pending file
        var pendingData: [String: Any] = [
            "id": requestId,
            "providerId": "claude",
            "sessionId": request.sessionId ?? "",
            "toolName": request.toolName,
            "projectPath": request.payload["cwd"] as? String ?? "",
            "summary": "AskUserQuestion",
            "matchValue": "",
            "receivedAt": Date().timeIntervalSince1970,
            "schemaVersion": 4,
            "kind": "question",
            "questions": questions.enumerated().map { (idx, q) -> [String: Any] in
                let opts = (q["options"] as? [[String: Any]])?.enumerated().map { (oi, opt) -> [String: Any] in
                    ["id": "q\(idx+1)-o\(oi+1)",
                     "title": opt["label"] as? String ?? "",
                     "detail": opt["description"] as? String as Any]
                } ?? []
                return [
                    "id": "q\(idx+1)",
                    "header": q["header"] as? String ?? "",
                    "prompt": q["question"] as? String ?? "",
                    "options": opts,
                    "isMultiple": q["multiSelect"] as? Bool ?? false,
                    "isOther": false,
                    "isSecret": false
                ]
            }
        ]

        // Write pending
        if let data = try? JSONSerialization.data(withJSONObject: pendingData, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: pendingPath, options: .atomic)
        }

        // Poll for response (blocking on this background thread)
        // SC's existing 500ms poll will pick up the pending, show popup,
        // user answers, SC writes response file. We read it here.
        let deadline = Date().addingTimeInterval(86400) // 24h timeout
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: responsePath.path) {
                if let data = try? Data(contentsOf: responsePath),
                   let decision = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let answers = decision["answers"] as? [String: String] ?? [:]

                    // Build updatedInput
                    var merged = toolInput
                    merged["answers"] = answers

                    // Clean up
                    try? FileManager.default.removeItem(at: pendingPath)
                    try? FileManager.default.removeItem(at: responsePath)

                    return .updatedInput(eventName: request.eventName, input: merged)
                }
            }
            if !FileManager.default.fileExists(atPath: pendingPath.path) {
                // Pending was removed (SC cancelled)
                return .allow(eventName: request.eventName)
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return .allow(eventName: request.eventName)
    }
}

// MARK: - Models

struct HookSocketRequest {
    let payload: [String: Any]

    var eventName: String { payload["hook_event_name"] as? String ?? "" }
    var toolName: String { payload["tool_name"] as? String ?? "" }
    var sessionId: String? { payload["session_id"] as? String }

    /// Dedup key: same question from PreToolUse and PermissionRequest
    /// should return the same answer. Key on tool_input + cwd (not event name).
    var dedupKey: String {
        let stable: [String: Any] = [
            "tool_name": toolName,
            "tool_input": payload["tool_input"] ?? "",
            "cwd": payload["cwd"] ?? ""
        ]
        let seed = (try? JSONSerialization.data(withJSONObject: stable, options: .sortedKeys))
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let hash = seed.utf8.reduce(into: Data()) { $0.append($1) }
        // Simple hash
        var h: UInt64 = 5381
        for byte in seed.utf8 { h = h &* 33 &+ UInt64(byte) }
        return String(format: "%016llx", h).suffix(16).description
    }
}

enum HookSocketResponse {
    case allow(eventName: String)
    case deny(eventName: String)
    case updatedInput(eventName: String, input: [String: Any])
    case empty

    var jsonData: Data? {
        switch self {
        case .allow(let eventName):
            let obj: [String: Any] = [
                "hookSpecificOutput": [
                    "hookEventName": eventName,
                    "decision": ["behavior": "allow"],
                    "permissionDecision": "allow"
                ]
            ]
            return try? JSONSerialization.data(withJSONObject: obj)

        case .deny(let eventName):
            let obj: [String: Any] = [
                "hookSpecificOutput": [
                    "hookEventName": eventName,
                    "decision": ["behavior": "deny", "message": "Denied in Session Cove."]
                ]
            ]
            return try? JSONSerialization.data(withJSONObject: obj)

        case .updatedInput(let eventName, let input):
            let obj: [String: Any] = [
                "hookSpecificOutput": [
                    "hookEventName": eventName,
                    "decision": [
                        "behavior": "allow",
                        "updatedInput": input
                    ]
                ]
            ]
            return try? JSONSerialization.data(withJSONObject: obj)

        case .empty:
            return "{}".data(using: .utf8)
        }
    }
}
