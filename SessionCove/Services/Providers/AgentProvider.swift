import Foundation

/// User-facing affordances and copy that vary per agent framework.
///
/// Each `AgentProvider` exposes a `UIAffordances` value so that views, hooks,
/// and notifications can render framework-appropriate strings without hard
/// coding "Claude" everywhere. Step 1 only introduces the type; later steps
/// will route UI through it.
struct UIAffordances: Sendable {
    /// Prefix used when looking up mascot art / sprite assets
    /// (e.g. "claude" → `claude_idle`, `claude_working`).
    let mascotPrefix: String

    /// Title shown in completion notifications / banners.
    let completionTitle: String

    /// Title shown when the agent asks the user a question
    /// (AskUserQuestion / interruption flow).
    let askQuestionTitle: String
}

/// On-disk organization of a provider's transcript files. Consumed by
/// `SessionScanner` to choose a traversal strategy. See
/// `AgentProvider.transcriptLayout` for per-shape semantics.
enum TranscriptLayout: Sendable {
    /// `<root>/<encodedProject>/<subpath>/<id>.jsonl` (Claude, Qoder, Cursor).
    case projectDirectories
    /// `<root>/YYYY/MM/DD/rollout-<ts>-<uuid>.jsonl` (Codex). Project cwd is
    /// stored inside each file rather than in a directory name.
    case flatDatePartitioned
}

/// Abstraction over a coding-agent framework that Session Cove can manage
/// (Claude Code, and — in future steps — Qoder, Codex, etc.).
///
/// Providers are intentionally value-like and `Sendable`. They describe
/// *where* the agent lives on disk and *how* to launch / resume it, but they
/// do not own runtime state. Runtime state stays in the existing services
/// (`SessionScanner`, `ProcessDetector`, `SessionResumer`, …) which will be
/// adapted to consult providers in later steps.
protocol AgentProvider: Sendable {
    /// Stable identifier used as the `providerId` in
    /// `HookPermissionRequest` and as a dictionary key in
    /// `AgentProviderRegistry`. Must not change once shipped.
    var id: String { get }

    /// Human-readable name (e.g. "Claude Code", "Qoder").
    var displayName: String { get }

    /// Process binary names (argv[0] / `comm` values) that identify a running
    /// agent of this provider. Used by `ProcessDetector` and the terminal
    /// ancestor walk to detect whether an agent is alive in a given tty.
    var processBinaryNames: [String] { get }

    /// Directory containing per-session transcript files (JSONL or
    /// equivalent). `SessionScanner` walks this tree to enumerate sessions.
    var transcriptRoot: URL { get }

    /// Sub-paths under each project directory where transcript JSONL files
    /// actually live. Default `[""]` (Claude shape: `<root>/<project>/<id>.jsonl`).
    /// Qoder uses `["", "transcript"]` because newer sessions land under a
    /// `transcript/` subdirectory while legacy sessions sit at the project
    /// root — both must be discovered.
    var transcriptSubpaths: [String] { get }

    /// Describes how transcript files are organized on disk so
    /// `SessionScanner` can pick the right traversal strategy.
    ///
    ///   * `.projectDirectories` (default) - Claude / Qoder shape:
    ///     `<root>/<encodedProject>/<subpath>/<id>.jsonl`. Each top-level
    ///     directory is one project island; the directory name encodes the
    ///     project path.
    ///   * `.flatDatePartitioned` - Codex shape:
    ///     `<root>/YYYY/MM/DD/rollout-<ts>-<uuid>.jsonl`. There is no
    ///     per-project directory; the project `cwd` lives *inside* each file
    ///     (the `session_meta` header). The scanner walks the tree, parses
    ///     every file, then groups the resulting records by their parsed
    ///     `projectPath` into islands.
    var transcriptLayout: TranscriptLayout { get }

    /// Settings file used by the framework's hook system, if any.
    /// `nil` when the framework does not expose hooks.
    var settingsPath: URL? { get }

    /// Shell command that resumes a previously-recorded session by id.
    func resumeCommand(sessionId: String) -> String

    /// Shell command that launches a fresh agent session (no resume).
    func bareLaunchCommand() -> String

    /// UI copy / asset hints for this provider.
    var ui: UIAffordances { get }

    /// Bundle identifier of the host macOS app (Electron IDE, etc.) when
    /// this provider lives inside a GUI app rather than a CLI. Used by
    /// the "open in <provider>" button to bring the IDE window to the
    /// foreground via `NSRunningApplication.activate`. `nil` for CLI
    /// agents (Claude Code) where focus is owned by the user's terminal.
    var bundleIdentifier: String? { get }

    /// True when the provider's PermissionRequest hook actually consumes
    /// our stdout decision (i.e. emitting `permissionDecision: allow`
    /// causes the agent to proceed). Claude Code = true; Qoder/Cursor =
    /// false because their sandbox dialogs are IDE-internal and ignore
    /// hook responses. The approval ping card uses this to decide
    /// whether to show 拒绝/始终允许/允许 buttons (true) or a single
    /// "打开 <provider>" focus button (false).
    var supportsExternalApproval: Bool { get }

    /// True when the approval ping card should offer a "始终允许" (always
    /// allow) button in addition to 允许/拒绝. Claude/Qoder support this via
    /// Session Cove's own allowlist + trusted-session shortcuts. Codex only
    /// understands a per-request allow/deny verdict from its hook (its
    /// `PermissionRequestDecisionWire.behavior` enum is exactly
    /// `allow`/`deny`), so the card hides the always-allow affordance for it.
    var supportsAlwaysAllow: Bool { get }
}

extension AgentProvider {
    /// Most providers (Claude, Cursor) drop transcripts directly under each
    /// project directory. Qoder/QoderWork override to add `"transcript"`.
    var transcriptSubpaths: [String] { [""] }

    /// Default: no GUI host (CLI-only providers like Claude).
    var bundleIdentifier: String? { nil }

    /// Default: the Claude/Qoder project-directory layout. Codex overrides
    /// to `.flatDatePartitioned`.
    var transcriptLayout: TranscriptLayout { .projectDirectories }

    /// Default: assume the agent honors hook stdout decisions, like
    /// Claude Code does. IDE-hosted agents that rely on internal sandbox
    /// dialogs (Qoder, Cursor) override to false.
    var supportsExternalApproval: Bool { true }

    /// Default: providers that honor external approval also support the
    /// always-allow shortcut (Claude/Qoder). Codex overrides to false.
    var supportsAlwaysAllow: Bool { true }
}
