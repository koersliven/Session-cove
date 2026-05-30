import Foundation

enum HookApprovalDecision: String, CaseIterable, Identifiable, Sendable {
    case deny
    case allow
    case allowSession
    case alwaysAllow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .deny: "Deny"
        case .allow: "Yes"
        case .allowSession: "Session"
        case .alwaysAllow: "Always"
        }
    }

    var detail: String {
        switch self {
        case .deny: "Reject this model or tool request."
        case .allow: "Allow once for this request."
        case .allowSession: "Allow similar requests for this session."
        case .alwaysAllow: "Always allow matching requests."
        }
    }
}

struct HookPermissionRequest: Identifiable, Equatable, Sendable, Codable {
    let id: String
    let sessionId: String?
    let toolName: String
    let projectPath: String
    let summary: String
    let matchValue: String
    let receivedAt: Date

    static func mock(for island: ProjectIsland?) -> HookPermissionRequest {
        HookPermissionRequest(
            id: UUID().uuidString,
            sessionId: nil,
            toolName: "Bash",
            projectPath: island?.path ?? "~/Work/session-cove",
            summary: "claude wants to run a model/tool request in this project island.",
            matchValue: "git status",
            receivedAt: Date()
        )
    }
}
