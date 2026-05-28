import Foundation
import SwiftUI

enum CoveUIMode: Equatable, Sendable {
    case compact
    case harborOverview
    case projectIsland
    case sessionFocus
    case permissionInterruption
}

enum CoveFrameSize: Equatable, Sendable {
    case compact      // 300x50
    case ping         // 360x220
    case expanded     // 520x480
}

enum CoveOpenReason: Equatable, Sendable {
    case click
    case hover
    case notification
    case boot
    case unknown
}

@Observable
final class CoveViewModel: @unchecked Sendable {
    var islands: [ProjectIsland] = []
    var uiMode: CoveUIMode = .compact
    var openReason: CoveOpenReason = .unknown
    var selectedIsland: ProjectIsland?
    var selectedSession: SessionRecord?
    var highlightedIslandID: String?
    var pendingHookRequest: HookPermissionRequest?
    var lastHookDecision: HookApprovalDecision?
    var hookIntegrationError: String?
    private var modeBeforeInterruption: CoveUIMode?

    private var watcher: SessionWatcher?
    private var refreshTask: Task<Void, Never>?
    private var hookPollTask: Task<Void, Never>?

    var isExpanded: Bool {
        uiMode != .compact && uiMode != .permissionInterruption
    }

    var frameSize: CoveFrameSize {
        switch uiMode {
        case .compact: .compact
        case .permissionInterruption: .ping
        default: .expanded
        }
    }

    var totalSessions: Int {
        islands.reduce(0) { $0 + $1.totalCount }
    }

    var activeSessions: Int {
        islands.reduce(0) { $0 + $1.activeCount }
    }

    var attentionIsland: ProjectIsland? {
        guard let pendingHookRequest else { return nil }
        return islands.first { $0.path == pendingHookRequest.projectPath }
    }

    var representativeIsland: ProjectIsland? {
        attentionIsland ?? islands.sorted { lhs, rhs in
            let lhsTime = lhs.sessions.first?.lastModified ?? .distantPast
            let rhsTime = rhs.sessions.first?.lastModified ?? .distantPast
            if lhs.activeCount != rhs.activeCount {
                return lhs.activeCount > rhs.activeCount
            }
            return lhsTime > rhsTime
        }.first
    }

    var representativeSession: SessionRecord? {
        if let selectedSession { return selectedSession }
        if let attentionIsland {
            return attentionIsland.sessions.sorted { $0.lastModified > $1.lastModified }.first
        }
        return representativeIsland?.sessions.sorted { lhs, rhs in
            if lhs.status != rhs.status {
                return statusPriority(lhs.status) < statusPriority(rhs.status)
            }
            return lhs.lastModified > rhs.lastModified
        }.first
    }

    func initialScan() async {
        await refresh()
        startWatching()
        startPeriodicRefresh()
    }

    @MainActor
    func refresh() async {
        var scanned = SessionScanner.scan()
        let candidateIds = Set(scanned.flatMap { $0.sessions.map(\.id) })
        let activeIds = ProcessDetector.shared.detectActiveSessionIds(candidateIds: candidateIds)
        ProcessDetector.shared.applyStatuses(activeIds: activeIds, to: &scanned)
        self.islands = scanned
    }

    func toggle() {
        if uiMode == .permissionInterruption {
            return
        } else if isExpanded {
            closeToCompact()
        } else {
            presentHarbor(reason: .click)
        }
    }

    func closeToCompact() {
        uiMode = .compact
        openReason = .unknown
        selectedIsland = nil
        selectedSession = nil
    }

    func presentHarbor(reason: CoveOpenReason) {
        uiMode = .harborOverview
        openReason = reason
        selectedIsland = nil
        selectedSession = nil
    }

    var highlightedIsland: ProjectIsland? {
        if let id = highlightedIslandID {
            return islands.first { $0.id == id }
        }
        return attentionIsland ?? islands.sorted { lhs, rhs in
            if lhs.activeCount != rhs.activeCount { return lhs.activeCount > rhs.activeCount }
            let lt = lhs.sessions.first?.lastModified ?? .distantPast
            let rt = rhs.sessions.first?.lastModified ?? .distantPast
            return lt > rt
        }.first
    }

    func highlightIsland(_ island: ProjectIsland) {
        highlightedIslandID = island.id
    }

    func selectIsland(_ island: ProjectIsland) {
        highlightedIslandID = island.id
        selectedIsland = island
        selectedSession = nil
    }

    func selectSession(_ session: SessionRecord) {
        selectedSession = session
        selectedIsland = islands.first { $0.id == session.projectDirEncoded || $0.path == session.projectPath } ?? selectedIsland
        uiMode = .sessionFocus
        openReason = .click
    }

    func resumeSession(_ session: SessionRecord) {
        print("[CoveViewModel] resumeSession tapped: \(session.id)")
        SessionResumer.resume(session: session)
    }

    func showMockHookRequest() {
        updatePendingHookRequest(HookPermissionRequest.mock(for: selectedIsland ?? islands.first))
    }

    func decideHookRequest(_ decision: HookApprovalDecision) {
        lastHookDecision = decision
        guard let request = pendingHookRequest else { return }
        do {
            try ClaudePermissionHook.resolve(request: request, decision: decision)
            updatePendingHookRequest(ClaudePermissionHook.pendingRequests().first)
        } catch {
            hookIntegrationError = error.localizedDescription
        }
    }

    @MainActor
    func startHookPolling() {
        hookPollTask?.cancel()
        hookPollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.updatePendingHookRequest(ClaudePermissionHook.pendingRequests().first)
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    func stopHookPolling() {
        hookPollTask?.cancel()
        hookPollTask = nil
    }

    func back() {
        if uiMode == .permissionInterruption {
            closeToCompact()
        } else if selectedSession != nil {
            selectedSession = nil
            uiMode = selectedIsland == nil ? .harborOverview : .projectIsland
        } else if selectedIsland != nil {
            selectedIsland = nil
            uiMode = .harborOverview
        } else {
            closeToCompact()
        }
    }

    private func updatePendingHookRequest(_ request: HookPermissionRequest?) {
        let previousID = pendingHookRequest?.id
        pendingHookRequest = request
        guard let request else {
            if uiMode == .permissionInterruption {
                if let restored = modeBeforeInterruption, restored != .permissionInterruption {
                    uiMode = restored
                    modeBeforeInterruption = nil
                } else {
                    uiMode = .compact
                }
            }
            return
        }

        if previousID != request.id || uiMode == .compact {
            if uiMode != .permissionInterruption {
                modeBeforeInterruption = uiMode
            }
            selectedIsland = islands.first { $0.path == request.projectPath } ?? selectedIsland
            selectedSession = selectedIsland?.sessions.sorted { $0.lastModified > $1.lastModified }.first ?? selectedSession
            uiMode = .permissionInterruption
            openReason = .notification
        }
    }

    private func statusPriority(_ status: SessionStatus) -> Int {
        switch status {
        case .active: 0
        case .recentlyIdle: 1
        case .archived: 2
        }
    }

    private func startWatching() {
        let watcher = SessionWatcher { [weak self] in
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
        watcher.start()
        self.watcher = watcher
    }

    private func startPeriodicRefresh() {
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                await self?.refresh()
            }
        }
    }
}
