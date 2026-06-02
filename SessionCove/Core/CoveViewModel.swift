import Foundation
import SwiftUI

enum CoveUIMode: Equatable, Sendable {
    case pet
    case compact
    case harborOverview
    case projectIsland
    case sessionFocus
    case permissionInterruption
}

enum CoveFrameSize: Equatable, Sendable {
    case pet          // 48x48
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

enum NotchStatus: Equatable {
    case closed
    case peeking
    case opened
    case popping
}

@Observable
final class CoveViewModel: @unchecked Sendable {
    var islands: [ProjectIsland] = []
    var uiMode: CoveUIMode = .pet
    var openReason: CoveOpenReason = .unknown
    var selectedIsland: ProjectIsland?
    var selectedSession: SessionRecord?
    var highlightedIslandID: String?
    var pendingHookRequest: HookPermissionRequest?
    var lastHookDecision: HookApprovalDecision?
    var hookIntegrationError: String?
    /// True when the user clicked the chevron on PermissionPingCard to see
    /// the full tool_input. Drives both pet ping height and notch popping
    /// height so the panel can grow from 72→240. Reset to false whenever
    /// `pendingHookRequest.id` changes.
    var approvalExpanded: Bool = false
    private var modeBeforeInterruption: CoveUIMode?

    private var watcher: SessionWatcher?
    private var refreshTask: Task<Void, Never>?
    private var hookPollTask: Task<Void, Never>?
    private var collapseTimer: Task<Void, Never>?
    private var completionDismissTimer: Task<Void, Never>?

    /// Invoked when the user finishes dragging the pet mascot.
    /// Window controller injects this on init to persist the new anchor without
    /// the view model needing a direct reference to AppKit window machinery.
    @ObservationIgnored
    var onPetDragEnded: (() -> Void)?

    var isExpanded: Bool {
        uiMode != .pet && uiMode != .compact && uiMode != .permissionInterruption
    }

    var frameSize: CoveFrameSize {
        switch uiMode {
        case .pet: .pet
        case .compact: .compact
        case .permissionInterruption: .ping
        default: .expanded
        }
    }

    /// Pet-mode ping frame height + notch popping height, both kind-aware
    /// and approval-expanded-aware. Single source of truth that hosts
    /// (CoveRootView pet, CoveNotchView notch) read off the view model.
    /// 72 (approval collapsed) / 240 (approval expanded) / 360 (question) / 120 (completion).
    var pingHeight: CGFloat {
        guard let kind = pendingHookRequest?.kind else { return 72 }
        switch kind {
        case .approval: return approvalExpanded ? 240 : 72
        case .question: return 360
        case .completion: return 120
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

    var pingExpandDirection: HorizontalEdge = .trailing
    var notchStatus: NotchStatus = .closed
    /// Mirror of `ModeTransitionState.shared.isTransitioning` for non-SwiftUI
    /// consumers that already hold a viewModel reference (e.g. NotchHoverDetector
    /// gates hover events while a mode swap is animating). WindowManager keeps
    /// both flags in sync.
    var modeTransitionInProgress: Bool = false
    var permissionInterruption: Bool = false

    func toggle() {
        if uiMode == .permissionInterruption {
            return
        } else if uiMode == .pet && pendingHookRequest != nil {
            modeBeforeInterruption = .pet
            uiMode = .permissionInterruption
            openReason = .click
            CoveSoundManager.shared.play(.sonarPing)
        } else if uiMode == .pet {
            presentHarbor(reason: .click)
            CoveSoundManager.shared.play(.waterSplash)
        } else if isExpanded {
            closeToPet()
            CoveSoundManager.shared.play(.waterSplash)
        } else if uiMode == .compact {
            presentHarbor(reason: .click)
            cancelCollapseTimer()
            CoveSoundManager.shared.play(.waterSplash)
        }
    }

    func petDragEnded() {
        // Notifies window controller to persist anchor (called from PetMascotView)
        onPetDragEnded?()
    }

    func closeToPet() {
        collapseTimer?.cancel()
        uiMode = .pet
        openReason = .unknown
        selectedIsland = nil
        selectedSession = nil
    }

    func closeToCompact() {
        closeToPet()
    }

    func presentHarbor(reason: CoveOpenReason) {
        cancelCollapseTimer()
        uiMode = .harborOverview
        openReason = reason
        selectedIsland = nil
        selectedSession = nil
    }

    private func resetCollapseTimer() {
        collapseTimer?.cancel()
        collapseTimer = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.closeToPet()
        }
    }

    private func cancelCollapseTimer() {
        collapseTimer?.cancel()
        collapseTimer = nil
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

    func deleteSession(_ session: SessionRecord) {
        let url = URL(fileURLWithPath: session.jsonlPath)
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            print("[CoveViewModel] deleteSession failed: \(error.localizedDescription)")
            return
        }
        CoveSoundManager.shared.play(.bubblePop)

        // Optimistic local removal so the UI updates immediately; FSEvents will
        // fire a refresh shortly which is idempotent.
        for index in islands.indices {
            islands[index].sessions.removeAll { $0.id == session.id }
        }
        islands.removeAll { $0.sessions.isEmpty }

        if selectedSession?.id == session.id {
            selectedSession = nil
            if uiMode == .sessionFocus {
                uiMode = selectedIsland == nil ? .harborOverview : .projectIsland
            }
        }
    }

    func showMockHookRequest() {
        updatePendingHookRequest(HookPermissionRequest.mock(for: selectedIsland ?? islands.first))
    }

    /// Mock for the chevron / expanded detail path (Feature 2).
    func showMockApprovalWithDetail() {
        updatePendingHookRequest(HookPermissionRequest.mockWithDetail(for: selectedIsland ?? islands.first))
    }

    /// Mock for the Stop / completion toast (Feature 1).
    func showMockCompletionRequest() {
        updatePendingHookRequest(HookPermissionRequest.mockCompletion(for: selectedIsland ?? islands.first))
    }

    /// Look up a SessionRecord by Claude session-id across all islands.
    /// Used by the completion toast's "打开 session" button to resume the
    /// just-finished session. Returns nil if the SessionScanner hasn't yet
    /// ingested the session's JSONL — caller falls back to launchNew.
    func findSession(byId id: String) -> SessionRecord? {
        guard !id.isEmpty else { return nil }
        for island in islands {
            if let match = island.sessions.first(where: { $0.id == id }) {
                return match
            }
        }
        return nil
    }

    /// Mock for the .question kind path (stage 5 verification). Builds a
    /// request with three representative questions — single-choice radio,
    /// multi-choice checkbox, and an isSecret SecureField — so the upcoming
    /// HookQuestionView (stage 6) can be exercised without the python hook.
    func showMockQuestionRequest() {
        let island = selectedIsland ?? islands.first
        let request = HookPermissionRequest(
            id: "mock-" + UUID().uuidString,
            sessionId: nil,
            toolName: "AskUserQuestion",
            projectPath: island?.path ?? "~/Work/session-cove",
            summary: "claude needs a few details before continuing.",
            matchValue: "",
            receivedAt: Date(),
            kind: .question,
            questions: [
                HookInterventionQuestion(
                    id: "q1",
                    header: "Region",
                    prompt: "Which region should this deploy land in?",
                    detail: "Pick the closest one to your users.",
                    options: [
                        HookInterventionOption(id: "us-east", title: "us-east", detail: "Virginia"),
                        HookInterventionOption(id: "eu-west", title: "eu-west", detail: "Ireland"),
                        HookInterventionOption(id: "ap-northeast", title: "ap-northeast", detail: "Tokyo")
                    ],
                    allowsMultiple: false,
                    allowsOther: false,
                    isSecret: false
                ),
                HookInterventionQuestion(
                    id: "q2",
                    header: "Components",
                    prompt: "Which components do you want regenerated?",
                    detail: nil,
                    options: [
                        HookInterventionOption(id: "api", title: "API gateway", detail: nil),
                        HookInterventionOption(id: "db", title: "Database schema", detail: nil),
                        HookInterventionOption(id: "ui", title: "UI bundle", detail: nil)
                    ],
                    allowsMultiple: true,
                    allowsOther: false,
                    isSecret: false
                ),
                HookInterventionQuestion(
                    id: "q3",
                    header: "Token",
                    prompt: "Paste the deploy token to continue.",
                    detail: "Will not be persisted to disk.",
                    options: [],
                    allowsMultiple: false,
                    allowsOther: false,
                    isSecret: true
                )
            ]
        )
        updatePendingHookRequest(request)
    }

    func decideHookRequest(_ decision: HookApprovalDecision) {
        lastHookDecision = decision
        CoveSoundManager.shared.play(.bubblePop)
        guard let request = pendingHookRequest else { return }
        do {
            try ClaudePermissionHook.resolve(request: request, decision: decision)
        } catch {
            hookIntegrationError = error.localizedDescription
        }
        // Completion-toast: `.openSession` focuses the live claude
        // terminal that just finished the turn. We deliberately use
        // `focusOrLaunch(sessionId:projectPath:)` instead of
        // `resumeSession` because the SessionScanner may not have ingested
        // the just-finished JSONL yet — but the claude *process* is still
        // alive in its terminal (waiting for the next prompt), so we can
        // locate it by `ps` regardless. Falling through to
        // `resumeSession(SessionRecord)` would have failed to find a record
        // and dropped to `launchNew`, opening a new terminal instead of
        // focusing the existing one.
        if request.kind == .completion, decision == .openSession,
           !request.projectPath.isEmpty {
            SessionResumer.focusOrLaunch(
                sessionId: request.sessionId ?? "",
                projectPath: request.projectPath
            )
        }
        updatePendingHookRequest(nil)
    }

    @MainActor
    func startHookPolling() {
        hookPollTask?.cancel()
        hookPollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let real = ClaudePermissionHook.pendingRequests().first
                // UI-injected mocks (Debug menu) are not on disk; the next poll
                // would return nil and clobber them, causing the popping panel
                // to vanish in ~500ms. Skip the overwrite when the current
                // pending is a mock and disk has nothing.
                let currentIsMock = self.pendingHookRequest?.id.hasPrefix("mock-") == true
                if real == nil && currentIsMock {
                    try? await Task.sleep(for: .milliseconds(500))
                    continue
                }
                self.updatePendingHookRequest(real)
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
            closeToPet()
        } else if selectedSession != nil {
            selectedSession = nil
            uiMode = selectedIsland == nil ? .harborOverview : .projectIsland
        } else if selectedIsland != nil {
            selectedIsland = nil
            uiMode = .harborOverview
        } else {
            closeToPet()
        }
    }

    private func updatePendingHookRequest(_ request: HookPermissionRequest?) {
        if pendingHookRequest == request { return }

        let previousID = pendingHookRequest?.id
        pendingHookRequest = request
        // Reset per-request UI state whenever the id changes (or clears).
        // approvalExpanded must not bleed from one request to the next; the
        // completion auto-dismiss timer must not fire after the toast it
        // belongs to has been replaced by something newer. When the new
        // request is an approval and the user opted into "默认展开", flip
        // approvalExpanded on instead of off so the detail panel renders
        // immediately without a chevron click.
        if previousID != request?.id {
            let preferExpanded = MainActor.assumeIsolated {
                CoveSettings.shared.approvalExpandByDefault
            }
            approvalExpanded = (request?.kind == .approval) && preferExpanded
            completionDismissTimer?.cancel()
            completionDismissTimer = nil
        }

        guard let request else {
            if uiMode == .permissionInterruption {
                if let restored = modeBeforeInterruption, restored != .permissionInterruption {
                    uiMode = restored
                    modeBeforeInterruption = nil
                } else {
                    uiMode = .pet
                }
            }
            return
        }

        if previousID != request.id || uiMode == .compact {
            // Suppress auto-presentation while the user is in a fullscreen
            // app — the yellow status dot still alerts them; they can hand-
            // toggle the pet to act when ready. Mirrors ping-island's
            // `shouldSuppressAutomaticPresentation`. FullscreenAppDetector
            // is @MainActor-isolated; all callers of this method run on
            // main (hookPolling Task @MainActor + SwiftUI button actions),
            // so assumeIsolated is safe.
            let suppressAutoPresent = MainActor.assumeIsolated {
                FullscreenAppDetector.shared.isFullscreen
            }

            // Completion toasts shouldn't preempt expanded modes
            // (.harborOverview/.projectIsland/.sessionFocus) — they're
            // notifications, not blockers. Yellow status dot still lights
            // and the user can hand-toggle when ready.
            let isCompletion = request.kind == .completion
            let modeAllowsCompletionPreempt: Bool = {
                switch uiMode {
                case .pet, .compact, .permissionInterruption: return true
                case .harborOverview, .projectIsland, .sessionFocus: return false
                }
            }()
            let allowAutoPresent = !suppressAutoPresent && (!isCompletion || modeAllowsCompletionPreempt)

            if uiMode != .permissionInterruption {
                modeBeforeInterruption = uiMode
            }
            selectedIsland = islands.first { $0.path == request.projectPath } ?? selectedIsland
            selectedSession = selectedIsland?.sessions.sorted { $0.lastModified > $1.lastModified }.first ?? selectedSession

            if allowAutoPresent {
                uiMode = .permissionInterruption
                openReason = .notification
            }
            CoveSoundManager.shared.play(.sonarPing)

            // Completion toast auto-dismisses after 30s so abandoned
            // notifications don't accumulate. Timer references the request
            // by id; if a fresher request lands first, the early `cancel`
            // above already invalidated this one's hook.
            if isCompletion {
                let targetID = request.id
                completionDismissTimer = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(30))
                    guard !Task.isCancelled, let self,
                          self.pendingHookRequest?.id == targetID else { return }
                    self.decideHookRequest(.acknowledge)
                }
            }
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
