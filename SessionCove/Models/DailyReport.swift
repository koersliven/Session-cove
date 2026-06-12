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
        /// Per-model breakdown for cost calculation.
        var modelBreakdown: [String: ModelUsage] = [:]

        struct ModelUsage: Codable, Sendable {
            var calls: Int = 0
            var inputTokens: Int = 0
            var outputTokens: Int = 0
        }

        /// Estimated API cost in USD.
        var estimatedCostUSD: Double {
            modelBreakdown.reduce(0) { total, entry in
                total + Self.costFor(input: entry.value.inputTokens, output: entry.value.outputTokens, model: entry.key)
            }
        }

        /// Per-model pricing per million tokens. Matches Anthropic API pricing (2026).
        /// DeepSeek pricing is estimated based on published tier.
        static func pricing(for model: String) -> (input: Double, output: Double) {
            if model.contains("Opus") || model.contains("opus") {
                return (15.0, 75.0)
            } else if model.contains("Sonnet") || model.contains("sonnet") {
                return (3.0, 15.0)
            } else if model.contains("Haiku") || model.contains("haiku") {
                return (0.80, 4.0)
            } else if model.contains("DeepSeek") || model.contains("deepseek") {
                return (1.5, 6.0)
            }
            return (5.0, 20.0)
        }

        static func costFor(input: Int, output: Int, model: String) -> Double {
            let p = pricing(for: model)
            return Double(input) / 1_000_000 * p.input + Double(output) / 1_000_000 * p.output
        }
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
