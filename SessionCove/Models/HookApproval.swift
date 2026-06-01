import Foundation

/// Discriminator for `HookPermissionRequest` payloads.
///
/// `.approval` (default) is the legacy yes/deny/always model used by the
/// PermissionRequest hook. `.question` covers AskUserQuestion /
/// AskFollowupQuestion events where Claude wants a typed answer instead of
/// a permission verdict — see `HookInterventionQuestion`.
enum HookRequestKind: String, Codable, Sendable {
    case approval
    case question
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

    /// Stable identifier written to disk and used for `Identifiable`.
    var serializedKey: String {
        switch self {
        case .deny: return "deny"
        case .allow: return "allow"
        case .allowSession: return "allowSession"
        case .alwaysAllow: return "alwaysAllow"
        case .answer: return "answer"
        }
    }

    var id: String { serializedKey }

    var title: String {
        switch self {
        case .deny: return "Deny"
        case .allow: return "Yes"
        case .allowSession: return "Session"
        case .alwaysAllow: return "Always"
        case .answer: return "Submit"
        }
    }

    var detail: String {
        switch self {
        case .deny: return "Reject this model or tool request."
        case .allow: return "Allow once for this request."
        case .allowSession: return "Allow similar requests for this session."
        case .alwaysAllow: return "Always allow matching requests."
        case .answer: return "Submit answers back to Claude."
        }
    }

    /// Buttons shown in approval UIs. `.answer` is intentionally excluded —
    /// it's emitted only from `HookQuestionView` (stage 6).
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
    /// `.approval` for legacy yes/deny payloads, `.question` for AskUserQuestion-style
    /// requests. Defaults to `.approval` so JSON written by older python hooks
    /// (no `kind` field) still decodes.
    var kind: HookRequestKind
    /// Empty for `.approval` requests. Populated only when `kind == .question`.
    var questions: [HookInterventionQuestion]

    init(
        id: String,
        sessionId: String?,
        toolName: String,
        projectPath: String,
        summary: String,
        matchValue: String,
        receivedAt: Date,
        kind: HookRequestKind = .approval,
        questions: [HookInterventionQuestion] = []
    ) {
        self.id = id
        self.sessionId = sessionId
        self.toolName = toolName
        self.projectPath = projectPath
        self.summary = summary
        self.matchValue = matchValue
        self.receivedAt = receivedAt
        self.kind = kind
        self.questions = questions
    }

    private enum CodingKeys: String, CodingKey {
        case id, sessionId, toolName, projectPath, summary, matchValue, receivedAt, kind, questions
    }

    /// Custom decoder so missing `kind` / `questions` keys (legacy schema v1)
    /// fall back to `.approval` / `[]` instead of throwing.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        self.toolName = try container.decode(String.self, forKey: .toolName)
        self.projectPath = try container.decode(String.self, forKey: .projectPath)
        self.summary = try container.decode(String.self, forKey: .summary)
        self.matchValue = try container.decode(String.self, forKey: .matchValue)
        self.receivedAt = try container.decode(Date.self, forKey: .receivedAt)
        self.kind = try container.decodeIfPresent(HookRequestKind.self, forKey: .kind) ?? .approval
        self.questions = try container.decodeIfPresent([HookInterventionQuestion].self, forKey: .questions) ?? []
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
            receivedAt: Date()
        )
    }
}
