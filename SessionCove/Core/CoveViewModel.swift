import Foundation
import SwiftUI

enum CoveUIMode: Equatable, Sendable {
    case compact
    case harborOverview
    case projectIsland
    case sessionFocus
    case permissionInterruption
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
    var pendingHookRequest: HookPermissionRequest?
    var lastHookDecision: HookApprovalDecision?
    var hookIntegrationError: String?
    private var modeBeforeInterruption: CoveUIMode?

    private var watcher: SessionWatcher?
    private var refreshTask: Task<Void, Never>?
    private var hookPollTask: Task<Void, Never>?

    var isExpanded: Bool {
        uiMode != .compact
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
        let now = Date()
        let activeThreshold: TimeInterval = 30
        let recentThreshold: TimeInterval = 24 * 60 * 60

        for i in scanned.indices {
            for j in scanned[i].sessions.indices {
                let session = scanned[i].sessions[j]
                let age = now.timeIntervalSince(session.lastModified)
                if age < activeThreshold {
                    scanned[i].sessions[j].status = .active
                } else if age < recentThreshold {
                    scanned[i].sessions[j].status = .recentlyIdle
                } else {
                    scanned[i].sessions[j].status = .archived
                }
            }
        }
        self.islands = scanned
    }

    func toggle() {
        if isExpanded {
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

    func selectIsland(_ island: ProjectIsland) {
        selectedIsland = island
        selectedSession = nil
        uiMode = .projectIsland
        openReason = .click
    }

    func selectSession(_ session: SessionRecord) {
        selectedSession = session
        selectedIsland = islands.first { $0.id == session.projectDirEncoded || $0.path == session.projectPath } ?? selectedIsland
        uiMode = .sessionFocus
        openReason = .click
    }

    func resumeSession(_ session: SessionRecord) {
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
        if pendingHookRequest != nil, uiMode == .permissionInterruption {
            presentHarbor(reason: .click)
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
                } else if selectedSession != nil {
                    uiMode = .sessionFocus
                } else if selectedIsland != nil {
                    uiMode = .projectIsland
                } else {
                    presentHarbor(reason: .notification)
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
