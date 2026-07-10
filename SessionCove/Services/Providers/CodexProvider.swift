import Foundation

/// `AgentProvider` profile for the OpenAI Codex CLI.
///
/// Codex differs from the Claude/Qoder family in every way that matters to
/// Session Cove's scanner, so it is NOT a "drop-in path swap" like Qoder:
///
///   * **Transcript layout.** Codex writes rollout files under a date tree,
///     `~/.codex/sessions/YYYY/MM/DD/rollout-<ts>-<uuid>.jsonl`, with no
///     per-project directory. The project `cwd` is stored *inside* each file
///     (the first `session_meta` line). Hence `transcriptLayout` is
///     `.flatDatePartitioned` and the scanner groups records by parsed cwd.
///   * **JSONL schema.** Lines are typed `session_meta` / `event_msg` /
///     `response_item`, not Claude's `permission-mode` / `user` / `ai-title`.
///     `SessionParser.parseCodex` handles that shape.
///   * **Resume command.** `codex resume <id>` (not `--resume`).
///   * **Hook/approval bridge.** Codex 0.143+ has a Claude-style hook
///     system: `~/.codex/hooks.json` (JSON) plus per-hook trust hashes in
///     `~/.codex/config.toml` `[hooks.state]`. Session Cove registers its
///     PermissionRequest + Stop hooks there, so `settingsPath` points at
///     `hooks.json` and `supportsExternalApproval` is `true` — the ping
///     card shows the 允许/拒绝 buttons (but NOT 始终允许; see below).
struct CodexProvider: AgentProvider {
    let id: String = "codex"
    let displayName: String = "Codex"
    let processBinaryNames: [String] = ["codex", "codex-tui"]

    var transcriptRoot: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
    }

    let transcriptLayout: TranscriptLayout = .flatDatePartitioned

    /// Codex 0.143+ ships a full hook system whose `hooks.json` uses the
    /// same Claude-style schema (top-level `hooks` dict keyed by PascalCase
    /// events, each an array of `{matcher, hooks:[{type,command,timeout}]}`).
    /// Session Cove registers its bridge into `~/.codex/hooks.json` for
    /// PermissionRequest (approval popups) + Stop (completion toasts).
    var settingsPath: URL? {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("hooks.json")
    }

    func resumeCommand(sessionId: String) -> String {
        "codex resume \(sessionId)"
    }

    func bareLaunchCommand() -> String {
        "codex"
    }

    let ui: UIAffordances = UIAffordances(
        mascotPrefix: "claude",
        completionTitle: "任务完成",
        askQuestionTitle: "Question from Codex"
    )

    /// Codex's PermissionRequest hook DOES consume our stdout verdict:
    /// emitting `{"hookSpecificOutput":{"hookEventName":"PermissionRequest",
    /// "decision":{"behavior":"allow"|"deny"}}}` from the hook makes Codex
    /// proceed or reject. So Session Cove can drive the approve/deny trio.
    let supportsExternalApproval: Bool = true

    /// Via the **app-server** path (Phase 2), Codex DOES support a
    /// session-scoped "always allow": the approval wire enum accepts
    /// `acceptForSession`. `CodexAppServerClient` maps SC's 始终允许
    /// decision onto `acceptForSession`, so the button is shown for Codex.
    ///
    /// (The older *hook* path could not express this — its
    /// `PermissionRequestDecisionWire.behavior` only had allow/deny — but the
    /// app-server path is now the primary Codex takeover, so we surface it.)
    let supportsAlwaysAllow: Bool = true
}
