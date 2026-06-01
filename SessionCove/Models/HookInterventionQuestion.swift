import Foundation

/// One selectable option for a `HookInterventionQuestion`.
///
/// Mirrors ping-island's `SessionInterventionOption` (see
/// `/Users/lipu/Work/ping-island/PingIsland/Models/SessionProvider.swift:695`)
/// but kept dependency-free so Session Cove can decode it from the python
/// hook payload without pulling in ping-island internals.
struct HookInterventionOption: Equatable, Sendable, Codable, Identifiable {
    let id: String
    let title: String
    let detail: String?
}

/// A single question Claude is asking the user via the AskUserQuestion /
/// AskFollowupQuestion tool. Multiple `HookInterventionQuestion`s may be
/// surfaced together inside one `HookPermissionRequest` (kind == .question).
///
/// - `allowsMultiple`: render as checkbox list when true, otherwise radio.
/// - `allowsOther`: append a free-text "Other..." field after the options.
/// - `isSecret`: render as `SecureField` and avoid persisting the answer to
///   the on-disk response file (redact in stage 5).
struct HookInterventionQuestion: Equatable, Sendable, Codable, Identifiable {
    let id: String
    let header: String
    let prompt: String
    let detail: String?
    let options: [HookInterventionOption]
    let allowsMultiple: Bool
    let allowsOther: Bool
    let isSecret: Bool
}
