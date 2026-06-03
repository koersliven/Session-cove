import Foundation

struct ProjectIsland: Identifiable, Hashable, Sendable {
    let id: String
    /// Stable id of the `AgentProvider` whose transcripts produced this
    /// island. Defaults to "claude" for backward compatibility with the
    /// pre-multi-provider scanner.
    let providerId: String
    let path: String
    let displayName: String
    var sessions: [SessionRecord] {
        didSet { recomputeCounts() }
    }

    /// Cached at init / mutation. Was a `computed` property using
    /// `sessions.filter`, which made every read O(n). It was being read 30×
    /// per second from `PetMascotView.body` via `representativeIsland`'s
    /// sort comparator, costing O(n² log n) per frame and pegging the main
    /// thread once a few dozen sessions accumulated. The visible symptom
    /// was the entire screen freezing because the floating panel's main
    /// thread, fully busy on this hot path, also stalled mouse-event
    /// dispatch through its global event monitors.
    private(set) var activeCount: Int = 0
    private(set) var recentCount: Int = 0

    var totalCount: Int { sessions.count }

    init(
        id: String,
        providerId: String = "claude",
        path: String,
        displayName: String,
        sessions: [SessionRecord]
    ) {
        self.id = id
        self.providerId = providerId
        self.path = path
        self.displayName = displayName
        self.sessions = sessions
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

    static func == (lhs: ProjectIsland, rhs: ProjectIsland) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
