import Foundation

/// `AgentProvider` profile for the QoderWork CLI.
///
/// QoderWork shares Qoder's hook + transcript + resume semantics but lives
/// under `~/.qoderwork/` and ships its own binary (`qoderwork`). For now
/// it reuses Qoder's mascot prefix; step 11 may diverge the visual asset
/// set if QoderWork gets dedicated artwork.
///
/// Like `QoderProvider`, this provider is registered but excluded from
/// `AgentProviderRegistry.enabled()` until the user-facing toggle lands.
/// No filesystem side effects (scans, hook installs) occur while it is
/// disabled.
struct QoderWorkProvider: AgentProvider {
    let id: String = "qoderwork"
    let displayName: String = "QoderWork"
    let processBinaryNames: [String] = ["qoderwork"]

    var transcriptRoot: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".qoderwork/projects", isDirectory: true)
    }

    var settingsPath: URL? {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".qoderwork/settings.json")
    }

    func resumeCommand(sessionId: String) -> String {
        "qoderwork --resume \(sessionId)"
    }

    func bareLaunchCommand() -> String {
        "qoderwork"
    }

    let ui: UIAffordances = UIAffordances(
        mascotPrefix: "qoder",
        completionTitle: "任务完成",
        askQuestionTitle: "Question from QoderWork"
    )
}
