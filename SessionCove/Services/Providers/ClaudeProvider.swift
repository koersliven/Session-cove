import Foundation

/// `AgentProvider` profile for Anthropic's Claude Code CLI.
///
/// All values mirror the existing hard-coded behavior used elsewhere in the
/// app (`~/.claude/projects` transcripts, `~/.claude/settings.json` hooks,
/// `claude --resume <id>` resume command). This struct is the single place
/// future steps will consult; existing call sites keep working unchanged
/// until they are migrated.
struct ClaudeProvider: AgentProvider {
    let id: String = "claude"
    let displayName: String = "Claude Code"
    let processBinaryNames: [String] = ["claude"]

    var transcriptRoot: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
    }

    var settingsPath: URL? {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
    }

    func resumeCommand(sessionId: String) -> String {
        "claude --resume \(sessionId)"
    }

    func bareLaunchCommand() -> String {
        "claude"
    }

    let ui: UIAffordances = UIAffordances(
        mascotPrefix: "claude",
        completionTitle: "任务完成",
        askQuestionTitle: "Question from Claude"
    )
}
