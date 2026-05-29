import SwiftUI

struct HarborMapOverviewView: View {
    @Bindable var viewModel: CoveViewModel
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
            mapHeader
            mapArea
            sessionDock
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { PixelOceanBackground() }
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
            ForEach(Array(mainPageIslands.enumerated()), id: \.element.id) { index, island in
                let slotIndex = slotOrder[index % slotOrder.count]
                let slot = mainSlots[slotIndex]
                let pos = CGPoint(x: slot.x * size.width, y: slot.y * size.height)
                let isSelected = island.id == viewModel.highlightedIsland?.id

                MapProjectIslandNode(
                    island: island,
                    isSelected: isSelected,
                    hasPendingPermission: viewModel.pendingHookRequest?.projectPath == island.path,
                    onTap: { viewModel.highlightIsland(island) }
                )
                .frame(width: nodeSize(for: island, selected: isSelected).width,
                       height: nodeSize(for: island, selected: isSelected).height)
                .position(pos)
            }

            if hiddenCount > 0 {
                moreReefButton(remaining: hiddenCount)
                    .position(x: size.width * 0.88, y: size.height * 0.22)
            }
        }
    }

    private func extendedMapContent(in size: CGSize) -> some View {
        ZStack {
            ForEach(Array(extendedPageIslands.enumerated()), id: \.element.id) { index, island in
                let slot = extendedSlots[index % extendedSlots.count]
                let pos = CGPoint(x: slot.x * size.width, y: slot.y * size.height)
                let isSelected = island.id == viewModel.highlightedIsland?.id

                StaggeredIslandNode(
                    island: island,
                    isSelected: isSelected,
                    hasPendingPermission: viewModel.pendingHookRequest?.projectPath == island.path,
                    onTap: { viewModel.highlightIsland(island) },
                    size: nodeSize(for: island, selected: isSelected),
                    delay: Double(index) * 0.06
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
        if let island = viewModel.highlightedIsland, !island.sessions.isEmpty {
            HarborSessionDock(
                island: island,
                onSessionTap: { viewModel.selectSession($0) },
                onResume: { viewModel.resumeSession($0) },
                onNewSession: { viewModel.newSession(for: island) }
            )
            .frame(height: 126)
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

    private var mainPageIslands: [ProjectIsland] {
        Array(sortedIslands.prefix(6))
    }

    private var extendedPageIslands: [ProjectIsland] {
        Array(sortedIslands.dropFirst(6).prefix(8))
    }

    private var hiddenCount: Int {
        max(0, viewModel.islands.count - 6)
    }

    private var sortedIslands: [ProjectIsland] {
        viewModel.islands.sorted { lhs, rhs in
            let lhsPending = viewModel.pendingHookRequest?.projectPath == lhs.path
            let rhsPending = viewModel.pendingHookRequest?.projectPath == rhs.path
            if lhsPending != rhsPending { return lhsPending }
            if lhs.activeCount != rhs.activeCount { return lhs.activeCount > rhs.activeCount }
            if lhs.recentCount != rhs.recentCount { return lhs.recentCount > rhs.recentCount }
            let lt = lhs.sessions.first?.lastModified ?? .distantPast
            let rt = rhs.sessions.first?.lastModified ?? .distantPast
            return lt > rt
        }
    }

    private func nodeSize(for island: ProjectIsland, selected: Bool) -> CGSize {
        if island.activeCount > 0 { return CGSize(width: 144, height: 88) }
        if island.recentCount > 0 { return CGSize(width: 132, height: 80) }
        return CGSize(width: 118, height: 70)
    }

    private var headerMascotState: PixelMascotState {
        if viewModel.pendingHookRequest != nil { return .attention }
        if viewModel.activeSessions > 0 { return .working }
        return .idle
    }
}

private struct StaggeredIslandNode: View {
    let island: ProjectIsland
    let isSelected: Bool
    let hasPendingPermission: Bool
    let onTap: () -> Void
    let size: CGSize
    let delay: Double

    @State private var visible = false

    var body: some View {
        MapProjectIslandNode(
            island: island,
            isSelected: isSelected,
            hasPendingPermission: hasPendingPermission,
            onTap: onTap
        )
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
