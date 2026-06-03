import Foundation

/// Discriminator for `HookPermissionRequest` payloads.
///
/// `.approval` (default) is the legacy yes/deny/always model used by the
/// PermissionRequest hook. `.question` covers AskUserQuestion /
/// AskFollowupQuestion events where Claude wants a typed answer instead of
/// a permission verdict — see `HookInterventionQuestion`.
/// `.completion` is fired by the Claude Code Stop hook when a session
/// finishes a turn — fire-and-forget toast (no response file written).
enum HookRequestKind: String, Codable, Sendable {
    case approval
    case question
    case completion
}

/// User decision on a hook request. Was a `String`-backed enum until we needed
/// to carry typed answers back from AskUserQuestion (`.answer`), at which
/// point we switched to associated values.
///
/// `serializedKey` replaces the previous synthesized `rawValue` for stable
/// on-disk JSON encoding; `staticDecisions` replaces `allCases` because
/// `.answer` should not appear as a button (it's submitted from the form).
enum HookApprovalDecision: Equatable, Identifiable, Sendable {
    case deny
    case allow
    case allowSession
    case alwaysAllow
    case answer(answers: [String: String])
    /// Completion-toast: user clicked 知道了. Pending file is removed; no
    /// response is written (the Stop hook is fire-and-forget Python-side).
    case acknowledge
    /// Completion-toast: user clicked 打开 session. Same disk semantics as
    /// `.acknowledge` but the view model also resumes the related session.
    case openSession

    /// Stable identifier written to disk and used for `Identifiable`.
    var serializedKey: String {
        switch self {
        case .deny: return "deny"
        case .allow: return "allow"
        case .allowSession: return "allowSession"
        case .alwaysAllow: return "alwaysAllow"
        case .answer: return "answer"
        case .acknowledge: return "acknowledge"
        case .openSession: return "openSession"
        }
    }

    var id: String { serializedKey }

    var title: String {
        switch self {
        case .deny: return "拒绝"
        case .allow: return "允许"
        case .allowSession: return "本次会话"
        case .alwaysAllow: return "始终允许"
        case .answer: return "提交"
        case .acknowledge: return "知道了"
        case .openSession: return "打开会话"
        }
    }

    var detail: String {
        switch self {
        case .deny: return "拒绝这次工具调用。"
        case .allow: return "本次允许这次工具调用。"
        case .allowSession: return "本次会话内放行相似的工具调用。"
        case .alwaysAllow: return "持久允许匹配的工具调用。"
        case .answer: return "提交答案回到 Claude。"
        case .acknowledge: return "忽略完成提示。"
        case .openSession: return "回到刚完成任务的会话。"
        }
    }

    /// Buttons shown in approval UIs. `.answer`/`.acknowledge`/`.openSession`
    /// are excluded — they're emitted only from their dedicated views
    /// (HookQuestionView, CompletionPingCard).
    static let staticDecisions: [HookApprovalDecision] = [.deny, .allow, .allowSession, .alwaysAllow]
}

struct HookPermissionRequest: Identifiable, Equatable, Sendable, Codable {
    let id: String
    let sessionId: String?
    let toolName: String
    let projectPath: String
    let summary: String
    let matchValue: String
    let receivedAt: Date
    /// Identifier of the agent provider that emitted this request (e.g. "claude").
    /// Defaults to `"claude"` so legacy v3 JSON without this field still decodes
    /// and surfaces under the Claude provider profile.
    var providerId: String
    /// `.approval` for legacy yes/deny payloads, `.question` for AskUserQuestion-style
    /// requests, `.completion` for Stop-hook task-done toasts. Defaults to
    /// `.approval` so JSON written by older python hooks (no `kind` field)
    /// still decodes.
    var kind: HookRequestKind
    /// Empty for `.approval`/`.completion` requests. Populated only when `kind == .question`.
    var questions: [HookInterventionQuestion]
    /// Pretty-printed JSON of the original `tool_input`, populated only for
    /// `.approval` requests (and only by python hook v3+). Powers the
    /// approval-card chevron/expanded panel. `nil` for legacy v2 payloads.
    var toolInputJSON: String?
    /// True if `toolInputJSON` was clipped at the python serialization cap (8 KB).
    var toolInputTruncated: Bool
    /// Stop-hook only: path to the Claude transcript JSONL of the finished turn.
    var transcriptPath: String?
    /// When the Stop event fired (separate from `receivedAt` which is set on file write).
    var completedAt: Date?
    /// Reserved for v2 — last assistant message preview for the completion toast.
    /// Python writes `null` today; populating it requires transcript tail parsing.
    var lastMessagePreview: String?

    init(
        id: String,
        sessionId: String?,
        toolName: String,
        projectPath: String,
        summary: String,
        matchValue: String,
        receivedAt: Date,
        providerId: String = "claude",
        kind: HookRequestKind = .approval,
        questions: [HookInterventionQuestion] = [],
        toolInputJSON: String? = nil,
        toolInputTruncated: Bool = false,
        transcriptPath: String? = nil,
        completedAt: Date? = nil,
        lastMessagePreview: String? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.toolName = toolName
        self.projectPath = projectPath
        self.summary = summary
        self.matchValue = matchValue
        self.receivedAt = receivedAt
        self.providerId = providerId
        self.kind = kind
        self.questions = questions
        self.toolInputJSON = toolInputJSON
        self.toolInputTruncated = toolInputTruncated
        self.transcriptPath = transcriptPath
        self.completedAt = completedAt
        self.lastMessagePreview = lastMessagePreview
    }

    private enum CodingKeys: String, CodingKey {
        case id, sessionId, toolName, projectPath, summary, matchValue, receivedAt
        case providerId
        case kind, questions
        case toolInputJSON, toolInputTruncated
        case transcriptPath, completedAt, lastMessagePreview
    }

    /// Custom decoder so missing keys (legacy schema v1/v2 payloads, or
    /// kind-specific fields that don't apply) fall back to safe defaults
    /// instead of throwing.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        self.toolName = try container.decode(String.self, forKey: .toolName)
        self.projectPath = try container.decode(String.self, forKey: .projectPath)
        self.summary = try container.decode(String.self, forKey: .summary)
        self.matchValue = try container.decode(String.self, forKey: .matchValue)
        self.receivedAt = try container.decode(Date.self, forKey: .receivedAt)
        self.providerId = try container.decodeIfPresent(String.self, forKey: .providerId) ?? "claude"
        self.kind = try container.decodeIfPresent(HookRequestKind.self, forKey: .kind) ?? .approval
        self.questions = try container.decodeIfPresent([HookInterventionQuestion].self, forKey: .questions) ?? []
        self.toolInputJSON = try container.decodeIfPresent(String.self, forKey: .toolInputJSON)
        self.toolInputTruncated = try container.decodeIfPresent(Bool.self, forKey: .toolInputTruncated) ?? false
        self.transcriptPath = try container.decodeIfPresent(String.self, forKey: .transcriptPath)
        self.completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        self.lastMessagePreview = try container.decodeIfPresent(String.self, forKey: .lastMessagePreview)
    }

    static func mock(for island: ProjectIsland?) -> HookPermissionRequest {
        // `mock-` prefix marks this as UI-injected (not on disk). hookPollTask
        // uses it to avoid clobbering the mock when the next poll returns nil.
        HookPermissionRequest(
            id: "mock-" + UUID().uuidString,
            sessionId: nil,
            toolName: "Bash",
            projectPath: island?.path ?? "~/Work/session-cove",
            summary: "claude wants to run a model/tool request in this project island.",
            matchValue: "git status",
            receivedAt: Date(),
            providerId: "claude"
        )
    }

    /// Mock with non-nil `toolInputJSON` so the chevron + expanded detail
    /// panel can be exercised via Debug menu without a real Claude payload.
    static func mockWithDetail(for island: ProjectIsland?) -> HookPermissionRequest {
        HookPermissionRequest(
            id: "mock-" + UUID().uuidString,
            sessionId: nil,
            toolName: "Bash",
            projectPath: island?.path ?? "~/Work/session-cove",
            summary: "Bash: git status --porcelain | head -50",
            matchValue: "git status --porcelain | head -50",
            receivedAt: Date(),
            providerId: "claude",
            toolInputJSON: """
            {
              "command": "git status --porcelain | head -50",
              "description": "Check repo dirty state, capped at 50 lines"
            }
            """,
            toolInputTruncated: false
        )
    }

    /// Stop-hook completion mock for the Debug menu.
    static func mockCompletion(for island: ProjectIsland?) -> HookPermissionRequest {
        HookPermissionRequest(
            id: "stop-mock-" + UUID().uuidString,
            sessionId: "mock-session-id-12345678",
            toolName: "Stop",
            projectPath: island?.path ?? "~/Work/session-cove",
            summary: "Session 完成了一回合任务",
            matchValue: "",
            receivedAt: Date(),
            providerId: "claude",
            kind: .completion,
            transcriptPath: nil,
            completedAt: Date()
        )
    }
}
