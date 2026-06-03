import Foundation

struct SessionRecord: Identifiable, Hashable, Sendable {
    let id: String
    /// Stable id of the `AgentProvider` that produced this transcript
    /// (e.g. "claude"). Defaults to "claude" so existing call sites that
    /// don't pass a provider keep working until they're migrated.
    let providerId: String
    let projectDirEncoded: String
    let projectPath: String
    let jsonlPath: String
    let firstUserMessage: String?
    let aiTitle: String?
    let timestamp: Date?
    let lastModified: Date
    let version: String?
    let gitBranch: String?
    var status: SessionStatus

    init(
        id: String,
        providerId: String = "claude",
        projectDirEncoded: String,
        projectPath: String,
        jsonlPath: String,
        firstUserMessage: String?,
        aiTitle: String?,
        timestamp: Date?,
        lastModified: Date,
        version: String?,
        gitBranch: String?,
        status: SessionStatus
    ) {
        self.id = id
        self.providerId = providerId
        self.projectDirEncoded = projectDirEncoded
        self.projectPath = projectPath
        self.jsonlPath = jsonlPath
        self.firstUserMessage = firstUserMessage
        self.aiTitle = aiTitle
        self.timestamp = timestamp
        self.lastModified = lastModified
        self.version = version
        self.gitBranch = gitBranch
        self.status = status
    }

    var displayTitle: String {
        if let title = aiTitle, !title.isEmpty {
            return title
        }
        if let msg = firstUserMessage {
            let cleaned = msg
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmed = cleaned.prefix(80)
            return trimmed.count < cleaned.count ? "\(trimmed)..." : String(trimmed)
        }
        return String(id.prefix(8))
    }

    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.localizedString(for: lastModified, relativeTo: Date())
    }

    static func == (lhs: SessionRecord, rhs: SessionRecord) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
