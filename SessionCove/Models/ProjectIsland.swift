import Foundation

struct ProjectIsland: Identifiable, Hashable, Sendable {
    let id: String
    let path: String
    let displayName: String
    var sessions: [SessionRecord]

    var activeCount: Int {
        sessions.filter { $0.status == .active }.count
    }

    var recentCount: Int {
        sessions.filter { $0.status == .recentlyIdle }.count
    }

    var totalCount: Int {
        sessions.count
    }

    static func == (lhs: ProjectIsland, rhs: ProjectIsland) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
