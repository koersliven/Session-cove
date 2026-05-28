import Foundation

struct SessionRecord: Identifiable, Hashable, Sendable {
    let id: String
    let projectDirEncoded: String
    let projectPath: String
    let firstUserMessage: String?
    let aiTitle: String?
    let timestamp: Date?
    let lastModified: Date
    let version: String?
    let gitBranch: String?
    var status: SessionStatus

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
