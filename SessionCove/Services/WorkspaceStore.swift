import Foundation

struct PendingClaim: Codable {
    let workspaceId: String
    let projectPath: String
    let claimedAt: Date
}

final class WorkspaceStore: ObservableObject {
    static let shared = WorkspaceStore()

    @Published private(set) var workspaces: [WorkspaceData] = []
    @Published private(set) var pendingClaims: [PendingClaim] = []

    private let fileURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".session-cove", isDirectory: true)
            .appendingPathComponent("workspaces.json")
    }()

    init() {
        loadFromDisk()
    }

    // MARK: - CRUD

    @discardableResult
    func create(name: String, folderPaths: [String]) -> WorkspaceData {
        let ws = WorkspaceData(
            id: UUID().uuidString,
            name: name,
            folderPaths: folderPaths,
            sessionIds: [],
            createdAt: Date()
        )
        workspaces.append(ws)
        saveToDisk()
        return ws
    }

    func update(id: String, name: String? = nil, folderPaths: [String]? = nil) {
        guard let idx = workspaces.firstIndex(where: { $0.id == id }) else { return }
        if let name { workspaces[idx].name = name }
        if let folderPaths { workspaces[idx].folderPaths = folderPaths }
        saveToDisk()
    }

    func delete(id: String) {
        workspaces.removeAll { $0.id == id }
        pendingClaims.removeAll { $0.workspaceId == id }
        saveToDisk()
    }

    // MARK: - Session Claiming

    func claimSession(workspaceId: String, sessionId: String) {
        guard let idx = workspaces.firstIndex(where: { $0.id == workspaceId }) else { return }
        if !workspaces[idx].sessionIds.contains(sessionId) {
            workspaces[idx].sessionIds.append(sessionId)
            saveToDisk()
        }
    }

    func unclaimSession(workspaceId: String, sessionId: String) {
        guard let idx = workspaces.firstIndex(where: { $0.id == workspaceId }) else { return }
        workspaces[idx].sessionIds.removeAll { $0 == sessionId }
        saveToDisk()
    }

    func allClaimedSessionIds() -> Set<String> {
        Set(workspaces.flatMap(\.sessionIds))
    }

    func workspace(owningSessionId sessionId: String) -> WorkspaceData? {
        workspaces.first { $0.sessionIds.contains(sessionId) }
    }

    // MARK: - Pending Claims

    func addPendingClaim(workspaceId: String, projectPath: String) {
        let claim = PendingClaim(
            workspaceId: workspaceId,
            projectPath: projectPath,
            claimedAt: Date()
        )
        pendingClaims.append(claim)
        saveToDisk()
    }

    func resolvePendingClaims(newSessions: [(id: String, projectPath: String)]) {
        let now = Date()
        var resolved: [Int] = []

        for (claimIdx, claim) in pendingClaims.enumerated() {
            guard now.timeIntervalSince(claim.claimedAt) < 60 else {
                resolved.append(claimIdx)
                continue
            }
            if let match = newSessions.first(where: { $0.projectPath == claim.projectPath }) {
                if !allClaimedSessionIds().contains(match.id) {
                    claimSession(workspaceId: claim.workspaceId, sessionId: match.id)
                }
                resolved.append(claimIdx)
            }
        }

        if !resolved.isEmpty {
            for idx in resolved.sorted().reversed() {
                pendingClaims.remove(at: idx)
            }
            saveToDisk()
        }
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        if let wsArray = json["workspaces"] as? [[String: Any]] {
            workspaces = wsArray.compactMap { dict in
                guard let id = dict["id"] as? String,
                      let name = dict["name"] as? String,
                      let folders = dict["folderPaths"] as? [String] else { return nil }
                let sessionIds = dict["sessionIds"] as? [String] ?? []
                let createdAt: Date
                if let ts = dict["createdAt"] as? Double {
                    createdAt = Date(timeIntervalSince1970: ts)
                } else {
                    createdAt = Date()
                }
                return WorkspaceData(
                    id: id, name: name, folderPaths: folders,
                    sessionIds: sessionIds, createdAt: createdAt
                )
            }
        }

        if let claimsArray = json["pendingClaims"] as? [[String: Any]] {
            pendingClaims = claimsArray.compactMap { dict in
                guard let wsId = dict["workspaceId"] as? String,
                      let path = dict["projectPath"] as? String,
                      let ts = dict["claimedAt"] as? Double else { return nil }
                return PendingClaim(
                    workspaceId: wsId, projectPath: path,
                    claimedAt: Date(timeIntervalSince1970: ts)
                )
            }
        }
    }

    private func saveToDisk() {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let wsArray: [[String: Any]] = workspaces.map { ws in
            [
                "id": ws.id,
                "name": ws.name,
                "folderPaths": ws.folderPaths,
                "sessionIds": ws.sessionIds,
                "createdAt": ws.createdAt.timeIntervalSince1970
            ]
        }

        let claimsArray: [[String: Any]] = pendingClaims.map { c in
            [
                "workspaceId": c.workspaceId,
                "projectPath": c.projectPath,
                "claimedAt": c.claimedAt.timeIntervalSince1970
            ]
        }

        let json: [String: Any] = [
            "workspaces": wsArray,
            "pendingClaims": claimsArray
        ]

        if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

/// Serializable workspace data (stored in JSON). The runtime `Workspace`
/// model adds resolved sessions on top of this.
struct WorkspaceData: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var folderPaths: [String]
    var sessionIds: [String]
    let createdAt: Date

    static func == (lhs: WorkspaceData, rhs: WorkspaceData) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
