import Foundation

/// Runtime workspace with resolved sessions. Built from `WorkspaceData`
/// (persisted) + session lookup during refresh.
struct Workspace: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let folderPaths: [String]
    let sessionIds: [String]
    let createdAt: Date

    var sessions: [SessionRecord] = []

    private(set) var activeCount: Int = 0
    private(set) var recentCount: Int = 0
    var totalCount: Int { sessions.count }

    var folderDisplayNames: [String] {
        folderPaths.map { ($0 as NSString).lastPathComponent }
    }

    init(data: WorkspaceData, sessions: [SessionRecord] = []) {
        self.id = data.id
        self.name = data.name
        self.folderPaths = data.folderPaths
        self.sessionIds = data.sessionIds
        self.createdAt = data.createdAt
        self.sessions = sessions
        recomputeCounts()
    }

    mutating func resolveSessions(from allSessions: [String: SessionRecord]) {
        sessions = sessionIds.compactMap { allSessions[$0] }
            .sorted { $0.lastModified > $1.lastModified }
        recomputeCounts()
    }

    private mutating func recomputeCounts() {
        var active = 0
        var recent = 0
        for s in sessions {
            switch s.status {
            case .active: active += 1
            case .recentlyIdle: recent += 1
            case .archived: break
            }
        }
        activeCount = active
        recentCount = recent
    }

    static func == (lhs: Workspace, rhs: Workspace) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
