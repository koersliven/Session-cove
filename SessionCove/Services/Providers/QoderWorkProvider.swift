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
    let processBinaryNames: [String] = [
        "qoderwork", "QoderWork", "QoderWork Helper", "QoderWork Helper (Plugin)"
    ]

    var transcriptRoot: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".qoderwork/projects", isDirectory: true)
    }

    /// Mirror QoderProvider — sessions live at the project root or under a
    /// `transcript/` subdirectory depending on QoderWork version.
    let transcriptSubpaths: [String] = ["", "transcript"]

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

    /// /Applications/QoderWork.app uses bundle id `com.qoder.work`.
    let bundleIdentifier: String? = "com.qoder.work"

    /// Same IDE-internal sandbox dialog as Qoder — hook responses do not
    /// drive the decision. Surface a focus button instead of approve/deny.
    let supportsExternalApproval: Bool = false
}
