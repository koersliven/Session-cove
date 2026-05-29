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
        CoveSoundManager.shared.play(.oceanAmbient)
        await refresh()
        startWatching()
        startPeriodicRefresh()
    }

    @MainActor
    func refresh() async {
        var scanned = SessionScanner.scan()
        let activePaths = ProcessDetector.shared.detectActiveProjectPaths()
        ProcessDetector.shared.applyStatuses(activeProjectPaths: activePaths, to: &scanned)
        self.islands = scanned
    }

    func toggle() {
        if uiMode == .permissionInterruption {
            return
        } else if isExpanded {
            closeToCompact()
            CoveSoundManager.shared.play(.waterSplash)
        } else {
            presentHarbor(reason: .click)
            CoveSoundManager.shared.play(.waterSplash)
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
        CoveSoundManager.shared.play(.treasureFound)
        SessionResumer.resume(session: session)
    }

    func newSession(for island: ProjectIsland) {
        print("[CoveViewModel] newSession tapped for: \(island.path)")
        CoveSoundManager.shared.play(.bubblePop)
        SessionResumer.launchNew(projectPath: island.path)
    }

    func showMockHookRequest() {
        updatePendingHookRequest(HookPermissionRequest.mock(for: selectedIsland ?? islands.first))
    }

    func decideHookRequest(_ decision: HookApprovalDecision) {
        lastHookDecision = decision
        CoveSoundManager.shared.play(.bubblePop)
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
        // Skip identical updates — without this, every 500ms poll re-assigns the
        // @Observable var and SwiftUI re-evaluates the body, which retriggers the
        // frameSize spring animation and causes the ping card to visibly jitter.
        if pendingHookRequest == request { return }

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
            CoveSoundManager.shared.play(.sonarPing)
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
                try? await Task.sleep(for: .seconds(15))
                await self?.refresh()
            }
        }
    }
}
