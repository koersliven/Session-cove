import Foundation

enum SessionStatus: Sendable, Equatable {
    case active
    case recentlyIdle
    case archived
}
