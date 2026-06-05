import Foundation

/// `AgentProvider` profile for the Cursor Agent.
///
/// Unlike Claude / Qoder, Cursor exposes a *different* hook schema and a
/// *different* transcript format, so it cannot reuse the Claude Python
/// `bridgeScript` dialect verbatim. The relevant divergences are:
///
///   * Hooks live at `~/.cursor/hooks.json` with a FLAT shape — top level
///     is a dict whose values are arrays of `{type, command}` entries.
///     There is NO Claude-style `{"hooks":[...]}` wrapper.
///   * Cursor has no `PermissionRequest` event, so the approval loop does
///     not apply. Only `stop` (and friends) are interesting for now.
///   * Transcripts at `~/.cursor/projects/<encoded>/<id>.jsonl` use a
///     `role` + `content[]` shape rather than Claude's typed lines.
///   * Resume CLI is `cursor agent resume <id>` when the `cursor` binary
///     is on PATH; otherwise the desktop bundle id
///     `com.todesktop.230313mzl4w4u92` can be opened. The fallback is
///     handled by `SessionResumer` in step 11.
///
/// This struct only describes those defaults. Step 9 registers the
/// provider but `AgentProviderRegistry.enabled()` still excludes it, so
/// no scanner / watcher / hook installer touches `~/.cursor/`.
struct CursorProvider: AgentProvider {
    let id: String = "cursor"
    let displayName: String = "Cursor"
    let processBinaryNames: [String] = ["cursor", "cursor-agent"]

    var transcriptRoot: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor/projects", isDirectory: true)
    }

    var settingsPath: URL? {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor/hooks.json")
    }

    func resumeCommand(sessionId: String) -> String {
        "cursor agent resume \(sessionId)"
    }

    func bareLaunchCommand() -> String {
        "cursor"
    }

    let ui: UIAffordances = UIAffordances(
        mascotPrefix: "cursor",
        completionTitle: "任务完成",
        askQuestionTitle: "Question from Cursor"
    )

    /// /Applications/Cursor.app — ToDesktop-wrapped Electron build.
    let bundleIdentifier: String? = "com.todesktop.230313mzl4w4u92"

    /// Empirically Cursor does NOT honor SC's stdout decision — even
    /// emitting both `decision` + `permission` keys with `timeout=60`
    /// the IDE still hangs as if waiting for an internal click. We
    /// retract the earlier docs-based assumption and treat Cursor like
    /// Qoder: SC popup is a "通知 + 回到 Cursor" reminder, the actual
    /// approval lives inside the IDE.
    let supportsExternalApproval: Bool = false
}
