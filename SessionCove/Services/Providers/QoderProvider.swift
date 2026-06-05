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
    /// Qoder is shipped as a macOS Electron IDE — its main process is named
    /// `Qoder` (not lowercase `qoder` like a CLI). Including both spellings
    /// keeps `ProcessDetector` matching whether the user runs Qoder.app or
    /// a future qoder CLI.
    let processBinaryNames: [String] = ["qoder", "Qoder", "Qoder Helper", "Qoder Helper (Plugin)"]

    var transcriptRoot: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".qoder/projects", isDirectory: true)
    }

    /// Qoder writes new sessions under `<project>/transcript/<id>.jsonl` but
    /// older sessions live at `<project>/<id>.jsonl`. Scan both so the harbor
    /// map shows the user's complete history.
    let transcriptSubpaths: [String] = ["", "transcript"]

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

    /// Qoder ships as a GUI Electron IDE; its bundle id is registered in
    /// /Applications/Qoder.app/Contents/Info.plist.
    let bundleIdentifier: String? = "com.qoder.ide"

    /// Qoder's "Run in sandbox" dialog is rendered by the IDE itself and
    /// does NOT respect PermissionRequest hook stdout decisions — verified
    /// empirically (we emit allow, the IDE still waits for an in-app
    /// click). Surface a "回到 Qoder" focus button instead of the
    /// approve/deny trio so the user knows the SC popup is a reminder,
    /// not an actual decision pipeline.
    let supportsExternalApproval: Bool = false
}
