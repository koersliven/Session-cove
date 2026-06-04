import Foundation

/// `AgentProvider` profile for the Qoder CLI.
///
/// Qoder is a near-clone of Claude Code: it uses the same hook events
/// (PermissionRequest / PreToolUse / Stop), the same `settings.json` schema,
/// the same transcript JSONL shape, and the same `--resume <id>` CLI. The
/// only differences that matter for Session Cove are the on-disk roots
/// (`~/.qoder/...`) and the binary name. The Python `bridgeScript`
/// `DIALECTS` table already aliases `qoder` to the Claude implementation,
/// so no Python-side change is needed when this provider is wired up.
///
/// Step 8 only registers this provider; it is intentionally excluded from
/// `AgentProviderRegistry.enabled()` until the user-facing toggle ships in
/// a later step. As long as `enabled()` does not return it, no scanner,
/// watcher, hook installer, or process detector will touch `~/.qoder/`.
struct QoderProvider: AgentProvider {
    let id: String = "qoder"
    let displayName: String = "Qoder"
    let processBinaryNames: [String] = ["qoder"]

    var transcriptRoot: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".qoder/projects", isDirectory: true)
    }

    var settingsPath: URL? {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".qoder/settings.json")
    }

    func resumeCommand(sessionId: String) -> String {
        "qoder --resume \(sessionId)"
    }

    func bareLaunchCommand() -> String {
        "qoder"
    }

    let ui: UIAffordances = UIAffordances(
        mascotPrefix: "qoder",
        completionTitle: "任务完成",
        askQuestionTitle: "Question from Qoder"
    )
}
