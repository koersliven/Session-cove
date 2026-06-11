import Foundation

struct DailyReport: Codable, Sendable {
    let date: Date
    let projects: [ProjectSummary]
    let rawMarkdown: String
    let generatedAt: Date
    let isFallback: Bool
    var tokenStats: TokenStats = TokenStats()

    struct ProjectSummary: Codable, Sendable, Identifiable {
        var id: String { path }
        let projectName: String
        let path: String
        let sessionCount: Int
        let firstActivity: Date
        let lastActivity: Date
        let highlights: [String]
        let gitBranches: [String]
    }

    struct TokenStats: Codable, Sendable {
        var apiCalls: Int = 0
        var totalInput: Int = 0
        var totalOutput: Int = 0
        var totalCacheRead: Int = 0
        var totalCacheWrite: Int = 0
    }
}

struct ReportSessionData: Sendable {
    let projectName: String
    let path: String
    let sessions: [ReportSessionEntry]
}

struct ReportSessionEntry: Sendable {
    let sessionId: String
    let aiTitle: String?
    let firstUserMessage: String?
    let gitBranch: String?
    let timestamp: Date?
    let lastModified: Date
    let userMessages: [String]
    var assistantOutcomes: [String] = []
    var messageCount: Int = 0
    var tokenStats: DailyReport.TokenStats = DailyReport.TokenStats()
}
