import Foundation

/// Persists user-defined custom names for sessions. Stored as a JSON
/// file at `~/.session-cove/session-names.json`. Custom names display
/// alongside (above) the AI-generated summary in the session list.
final class SessionNameStore: ObservableObject {
    static let shared = SessionNameStore()

    @Published private(set) var names: [String: String] = [:]

    private let fileURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".session-cove", isDirectory: true)
            .appendingPathComponent("session-names.json")
    }()

    init() {
        loadFromDisk()
    }

    /// Get the custom name for a session (nil if not set).
    func name(for sessionId: String) -> String? {
        names[sessionId]
    }

    /// Set or update a custom name. Pass nil to remove.
    func setName(_ name: String?, for sessionId: String) {
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            names[sessionId] = name.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            names.removeValue(forKey: sessionId)
        }
        saveToDisk()
    }

    /// Remove names for sessions that no longer exist (garbage collect).
    func prune(existingSessionIds: Set<String>) {
        let before = names.count
        names = names.filter { existingSessionIds.contains($0.key) }
        if names.count != before {
            saveToDisk()
        }
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return
        }
        names = decoded
    }

    private func saveToDisk() {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(
            withJSONObject: names,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
