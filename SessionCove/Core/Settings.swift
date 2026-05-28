import Foundation
import SwiftUI

final class CoveSettings: ObservableObject {
    static let shared = CoveSettings()

    @AppStorage("preferredTerminal") var preferredTerminal: String = "auto"
    @AppStorage("showArchivedSessions") var showArchivedSessions: Bool = true
    @AppStorage("compactMode") var compactMode: Bool = false
}
