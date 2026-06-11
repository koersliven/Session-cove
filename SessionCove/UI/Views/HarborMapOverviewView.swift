import SwiftUI

struct HarborMapOverviewView: View {
    @Bindable var viewModel: CoveViewModel
    @ObservedObject private var updateChecker = UpdateChecker.shared
    var showsHeader: Bool = true
    /// Compact mode: hides the session dock and shrinks island nodes so the
    /// view fits inside the notch peeking panel (480×~176pt body area). The
    /// island node positions are relative to the container, so they scale
    /// naturally — only the node sprites themselves need explicit shrinking.
    var compact: Bool = false
    /// Fires when any island node is tapped. Peeking notch wires this to
    /// escalate to `.opened`, so a click on the mini harbor expands to full.
    var onAnyIslandTap: (() -> Void)? = nil
    @State private var mapPage: MapPage = .main

    private enum MapPage {
        case main
        case extended
    }

    private let mainSlots: [CGPoint] = [
        CGPoint(x: 0.26, y: 0.30),
        CGPoint(x: 0.72, y: 0.26),
        CGPoint(x: 0.48, y: 0.52),
        CGPoint(x: 0.20, y: 0.70),
        CGPoint(x: 0.76, y: 0.66),
        CGPoint(x: 0.46, y: 0.84)
    ]

    private let extendedSlots: [CGPoint] = [
        CGPoint(x: 0.28, y: 0.30),
        CGPoint(x: 0.68, y: 0.20),
        CGPoint(x: 0.44, y: 0.40),
        CGPoint(x: 0.80, y: 0.42),
        CGPoint(x: 0.26, y: 0.58),
        CGPoint(x: 0.64, y: 0.60),
        CGPoint(x: 0.42, y: 0.78),
        CGPoint(x: 0.78, y: 0.80)
    ]

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader { mapHeader }
            mapArea
            if !compact { sessionDock }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { PixelOceanBackground() }
        .alert(
            "Delete Workspace?",
            isPresented: Binding(
                get: { viewModel.pendingWorkspaceDeletion != nil },
                set: { if !$0 { viewModel.cancelDeleteWorkspace() } }
            )
        ) {
            Button("Cancel", role: .cancel) { viewModel.cancelDeleteWorkspace() }
            Button("Delete", role: .destructive) { viewModel.confirmDeleteWorkspace() }
        } message: {
            Text("The workspace directory and all its sessions will be moved to Trash.")
        }
    }

    // MARK: - Header

    private var mapHeader: some View {
        HStack(spacing: 10) {
            CoveMascotView(state: headerMascotState, scale: .compact)

            Text("Session Cove")
                .font(.system(size: 13, weight: .black, design: .monospaced))
                .foregroundStyle(.white)

            Spacer()

            if viewModel.activeSessions > 0 {
                HStack(spacing: 4) {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text("\(viewModel.activeSessions)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.green)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(.green.opacity(0.12))
                        .overlay(Capsule().stroke(.green.opacity(0.3), lineWidth: 1))
                )
            }

            Button {
                Task { @MainActor in
                    DailyReportWindowController.shared.show(viewModel: viewModel)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "water.waves")
                        .font(.system(size: 9))
                    Text("日报")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                }
                .foregroundStyle(viewModel.hasUnreadReport ? .cyan : .white.opacity(0.7))
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(viewModel.hasUnreadReport ? Color.cyan.opacity(0.15) : Color.white.opacity(0.06))
                        .overlay(Capsule().stroke(
                            viewModel.hasUnreadReport ? Color.cyan.opacity(0.4) : Color.white.opacity(0.15),
                            lineWidth: 1
                        ))
                )
            }
            .buttonStyle(.plain)

            if case .available(let version, _, _) = updateChecker.state, !updateChecker.dismissed {
                updateBadge(version: version)
            } else if case .downloading(let progress) = updateChecker.state {
                downloadingBadge(progress: progress)
            }

            if viewModel.deferredRequestId != nil {
                Button {
                    viewModel.deferredRequestId = nil
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 9))
                        Text("待处理")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(PixelPalette.alert)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(PixelPalette.alert.opacity(0.12))
                            .overlay(Capsule().stroke(PixelPalette.alert.opacity(0.4), lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)
            }

            Button {
                Task { @MainActor in
                    NewSessionWindowController.shared.show(viewModel: viewModel)
                }
            } label: {
                HStack(spacing: 2) {
                    Text("+")
                        .font(.system(size: 10, weight: .black))
                    Text("NEW")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color(red: 0.10, green: 0.45, blue: 0.30))
                        .overlay(Capsule().stroke(PixelPalette.grass.opacity(0.5), lineWidth: 1))
                )
            }
            .buttonStyle(.plain)

            Button {
                Task { @MainActor in
                    WorkspaceEditorWindowController.shared.show(viewModel: viewModel)
                }
            } label: {
                HStack(spacing: 2) {
                    Text("+")
                        .font(.system(size: 10, weight: .black))
                    Text("Workspace")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                }
                .foregroundStyle(Color(red: 0.90, green: 0.72, blue: 0.20))
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color(red: 0.90, green: 0.72, blue: 0.20).opacity(0.12))
                        .overlay(Capsule().stroke(Color(red: 0.90, green: 0.72, blue: 0.20).opacity(0.4), lineWidth: 1))
                )
            }
            .buttonStyle(.plain)

            Button { viewModel.closeToCompact() } label: {
                Text("×")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.15))
    }

    // MARK: - Map Area

    private var mapArea: some View {
        GeometryReader { geo in
            ZStack {
                switch mapPage {
                case .main:
                    mainMapContent(in: geo.size)
                        .transition(.opacity)
                case .extended:
                    extendedMapContent(in: geo.size)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: mapPage)
        }
        .frame(maxHeight: .infinity)
    }

    private let slotOrder = [2, 0, 1, 3, 4, 5]

    private func mainMapContent(in size: CGSize) -> some View {
        ZStack {
            ForEach(Array(mainPageItems.enumerated()), id: \.element.id) { index, item in
                let slotIndex = slotOrder[index % slotOrder.count]
                let slot = mainSlots[slotIndex]
                let pos = CGPoint(x: slot.x * size.width, y: slot.y * size.height)

                mapNode(for: item, compact: compact)
                    .frame(width: nodeSize(for: item, selected: isItemSelected(item)).width,
                           height: nodeSize(for: item, selected: isItemSelected(item)).height)
                    .position(pos)
            }

            if hiddenCount > 0 && !compact {
                moreReefButton(remaining: hiddenCount)
                    .position(x: size.width * 0.88, y: size.height * 0.22)
            }
        }
    }

    private func extendedMapContent(in size: CGSize) -> some View {
        ZStack {
            ForEach(Array(extendedPageItems.enumerated()), id: \.element.id) { index, item in
                let slot = extendedSlots[index % extendedSlots.count]
                let pos = CGPoint(x: slot.x * size.width, y: slot.y * size.height)

                StaggeredMapNode(
                    item: item,
                    isSelected: isItemSelected(item),
                    compact: compact,
                    onTap: { tapItem(item) },
                    size: nodeSize(for: item, selected: isItemSelected(item)),
                    delay: Double(index) * 0.06,
                    hasPendingPermission: itemHasPending(item),
                    onDelete: { deleteItem(item) }
                )
                .position(pos)
            }

            Button {
                mapPage = .main
            } label: {
                HStack(spacing: 4) {
                    Text("‹")
                        .font(.system(size: 14, weight: .bold))
                    Text("MAP")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                }
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(PixelPalette.hud.opacity(0.95))
                        .overlay(Capsule().stroke(PixelPalette.hudEdge.opacity(0.6), lineWidth: 1))
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .position(x: 50, y: 20)
            .zIndex(100)
        }
    }

    // MARK: - Session Dock

    @ViewBuilder
    private var sessionDock: some View {
        if let ws = viewModel.highlightedWorkspace {
            WorkspaceSessionDock(
                workspace: ws,
                onSessionTap: { viewModel.selectSession($0) },
                onResume: { viewModel.resumeSession($0) },
                onDelete: { viewModel.deleteSession($0) },
                onNewSession: { folder in viewModel.newSessionInWorkspace(ws, folderPath: folder) }
            )
            .frame(height: 146)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if let island = viewModel.highlightedIsland, !island.sessions.isEmpty {
            HarborSessionDock(
                island: island,
                onSessionTap: { viewModel.selectSession($0) },
                onResume: { viewModel.resumeSession($0) },
                onDelete: { viewModel.deleteSession($0) },
                onNewSession: { viewModel.newSession(for: island) }
            )
            .frame(height: 146)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            emptyDock
        }
    }

    private var emptyDock: some View {
        HStack(spacing: 6) {
            CoveMascotView(state: .sleeping, scale: .row)
            Text("Select an island to view sessions")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(height: 52)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.2))
    }

    // MARK: - More Reef Button

    private func moreReefButton(remaining: Int) -> some View {
        Button {
            mapPage = .extended
        } label: {
            VStack(spacing: 4) {
                MoreReefArrow()
                    .frame(width: 42, height: 20)

                Text("+\(remaining)")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))

                PixelIslandSprite(mood: .archived)
                    .frame(width: 70, height: 42)
                    .opacity(0.5)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data

    enum MapItem: Identifiable {
        case island(ProjectIsland)
        case workspace(Workspace)

        var id: String {
            switch self {
            case .island(let i): "island:\(i.id)"
            case .workspace(let w): "ws:\(w.id)"
            }
        }

        var activeCount: Int {
            switch self {
            case .island(let i): i.activeCount
            case .workspace(let w): w.activeCount
            }
        }

        var recentCount: Int {
            switch self {
            case .island(let i): i.recentCount
            case .workspace(let w): w.recentCount
            }
        }

        var latestModified: Date {
            switch self {
            case .island(let i): i.sessions.first?.lastModified ?? .distantPast
            case .workspace(let w): w.sessions.first?.lastModified ?? .distantPast
            }
        }
    }

    private var sortedItems: [MapItem] {
        var items: [MapItem] = viewModel.islands.map { .island($0) }
            + viewModel.workspaces.map { .workspace($0) }
        items.sort { lhs, rhs in
            if lhs.activeCount != rhs.activeCount { return lhs.activeCount > rhs.activeCount }
            if lhs.recentCount != rhs.recentCount { return lhs.recentCount > rhs.recentCount }
            return lhs.latestModified > rhs.latestModified
        }
        return items
    }

    private var mainPageItems: [MapItem] {
        Array(sortedItems.prefix(6))
    }

    private var extendedPageItems: [MapItem] {
        Array(sortedItems.dropFirst(6).prefix(8))
    }

    private var hiddenCount: Int {
        max(0, sortedItems.count - 6)
    }

    private func nodeSize(for item: MapItem, selected: Bool) -> CGSize {
        let scale: CGFloat = compact ? 0.55 : 1.0
        if item.activeCount > 0 { return CGSize(width: 144 * scale, height: 88 * scale) }
        if item.recentCount > 0 { return CGSize(width: 132 * scale, height: 80 * scale) }
        return CGSize(width: 118 * scale, height: 70 * scale)
    }

    private func isItemSelected(_ item: MapItem) -> Bool {
        switch item {
        case .island(let i): i.id == viewModel.highlightedIsland?.id
        case .workspace(let w): w.id == viewModel.highlightedWorkspaceID
        }
    }

    private func tapItem(_ item: MapItem) {
        switch item {
        case .island(let island):
            viewModel.highlightIsland(island)
        case .workspace(let ws):
            viewModel.highlightWorkspace(ws)
        }
        onAnyIslandTap?()
    }

    private func itemHasPending(_ item: MapItem) -> Bool {
        switch item {
        case .island(let i): viewModel.pendingHookRequest?.projectPath == i.path
        case .workspace(let w): w.folderPaths.contains(where: { viewModel.pendingHookRequest?.projectPath == $0 })
        }
    }

    private func deleteItem(_ item: MapItem) {
        switch item {
        case .island(let island):
            viewModel.deleteIsland(island)
        case .workspace(let ws):
            viewModel.requestDeleteWorkspace(id: ws.id)
        }
    }

    @ViewBuilder
    private func mapNode(for item: MapItem, compact: Bool) -> some View {
        switch item {
        case .island(let island):
            MapProjectIslandNode(
                island: island,
                isSelected: isItemSelected(item),
                hasPendingPermission: itemHasPending(item),
                compact: compact,
                onTap: { tapItem(item) },
                onDelete: { viewModel.deleteIsland(island) }
            )
        case .workspace(let ws):
            MapWorkspaceNode(
                workspace: ws,
                isSelected: isItemSelected(item),
                compact: compact,
                onTap: { tapItem(item) },
                onDelete: { viewModel.requestDeleteWorkspace(id: ws.id) }
            )
        }
    }

    @ViewBuilder
    private func updateBadge(version: String) -> some View {
        Button {
            if case .available(_, let url, let notes) = updateChecker.state {
                showUpdateAlert(version: version, url: url, notes: notes)
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 8))
                Text("更新")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
            }
            .foregroundStyle(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(.orange.opacity(0.15))
                    .overlay(Capsule().stroke(.orange.opacity(0.4), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func downloadingBadge(progress: Double) -> some View {
        HStack(spacing: 3) {
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 10, height: 10)
            Text("\(Int(progress * 100))%")
                .font(.system(size: 8, weight: .black, design: .monospaced))
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Capsule().fill(.orange.opacity(0.12)))
    }

    private func showUpdateAlert(version: String, url: URL, notes: String?) {
        let alert = NSAlert()
        alert.messageText = "Session Cove v\(version) 可用"
        alert.informativeText = notes ?? "有新版本可以更新。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "立即更新")
        alert.addButton(withTitle: "稍后再说")
        alert.addButton(withTitle: "不再提醒")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            UpdateChecker.shared.downloadAndInstall(dmgURL: url)
        case .alertThirdButtonReturn:
            UpdateChecker.shared.dismiss()
        default:
            break
        }
    }

    private var headerMascotState: PixelMascotState {
        if viewModel.pendingHookRequest != nil { return .attention }
        if viewModel.activeSessions > 0 { return .working }
        return .idle
    }
}

private struct StaggeredMapNode: View {
    let item: HarborMapOverviewView.MapItem
    let isSelected: Bool
    var compact: Bool = false
    let onTap: () -> Void
    let size: CGSize
    let delay: Double
    var hasPendingPermission: Bool = false
    var onDelete: (() -> Void)? = nil

    @State private var visible = false

    var body: some View {
        Group {
            switch item {
            case .island(let island):
                MapProjectIslandNode(
                    island: island,
                    isSelected: isSelected,
                    hasPendingPermission: hasPendingPermission,
                    compact: compact,
                    onTap: onTap,
                    onDelete: onDelete
                )
            case .workspace(let ws):
                MapWorkspaceNode(
                    workspace: ws,
                    isSelected: isSelected,
                    compact: compact,
                    onTap: onTap,
                    onDelete: onDelete
                )
            }
        }
        .frame(width: size.width, height: size.height)
        .opacity(visible ? 1 : 0)
        .scaleEffect(visible ? 1 : 0.7)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    visible = true
                }
            }
        }
        .onDisappear { visible = false }
    }
}

struct MoreReefArrow: View {
    @State private var drift: CGFloat = 0

    private let spongeYellow = Color(red: 0.98, green: 0.85, blue: 0.15)

    var body: some View {
        HStack(spacing: 4) {
            Text("›")
                .font(.system(size: 14, weight: .bold))
            Text("MORE")
                .font(.system(size: 9, weight: .black, design: .monospaced))
        }
        .fixedSize()
        .foregroundStyle(Color(red: 0.25, green: 0.15, blue: 0.0))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(spongeYellow)
                .overlay(Capsule().stroke(Color(red: 0.85, green: 0.70, blue: 0.05), lineWidth: 1.5))
        )
        .fixedSize()
        .offset(x: drift)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                drift = 2
            }
        }
    }
}
