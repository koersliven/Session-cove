import SwiftUI

/// Visual content of the Notch panel across its four state-machine states.
/// `closed` (224×32 notch) → `peeking` (480×220 summary) → `opened` (600×480
/// harbor preview). `popping` is a permission-ping variant — for PR 4 it
/// renders the same geometry as `opened` (PR 5/6 wires the cardlet UX).
///
/// The shared NotchShape and octopus head use `matchedGeometryEffect` so
/// SwiftUI morphs them smoothly across state transitions instead of cross-fading.
struct CoveNotchView: View {
    @Bindable var viewModel: CoveViewModel
    @Namespace private var animationNamespace

    var body: some View {
        ZStack(alignment: .top) {
            // Color.clear stretches the ZStack to fill the panel; closed-state
            // content (224×32) then sits at the .top while the rest passes
            // through (panel.ignoresMouseEvents = true in closed anyway).
            Color.clear
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(animation(for: viewModel.notchStatus), value: viewModel.notchStatus)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.notchStatus {
        case .closed:
            ClosedNotchContent(viewModel: viewModel, namespace: animationNamespace)
                .onTapGesture { viewModel.notchStatus = .opened }
        case .peeking:
            PeekingNotchContent(viewModel: viewModel, namespace: animationNamespace)
                .onTapGesture { viewModel.notchStatus = .opened }
        case .opened, .popping:
            OpenedNotchContent(viewModel: viewModel, namespace: animationNamespace)
        }
    }

    /// Per-destination spring; matches the spec's animation table (rows 191-200).
    /// Note: opened → closed (spring 0.45/1.0) and peeking → closed (easeOut)
    /// share a destination here — PR 4 uses a single closed-spring; PR 5 may
    /// refine via custom transition modifiers if the difference is perceptible.
    private func animation(for status: NotchStatus) -> Animation {
        switch status {
        case .closed:  return .spring(response: 0.45, dampingFraction: 1.0,  blendDuration: 0)
        case .peeking: return .spring(response: 0.42, dampingFraction: 0.82, blendDuration: 0)
        case .opened:  return .spring(response: 0.42, dampingFraction: 0.78, blendDuration: 0)
        case .popping: return .spring(response: 0.40, dampingFraction: 0.85, blendDuration: 0)
        }
    }
}

// MARK: - Closed state

private struct ClosedNotchContent: View {
    let viewModel: CoveViewModel
    let namespace: Namespace.ID

    var body: some View {
        ZStack {
            NotchShape.closed
                .fill(Color.black)
                .matchedGeometryEffect(id: CoveNotchAnimationID.shape, in: namespace)
            HStack(spacing: 4) {
                octopusHead
                    .matchedGeometryEffect(id: CoveNotchAnimationID.octopus, in: namespace)
                statusDot
            }
            .padding(.horizontal, 8)
        }
        .frame(width: 224, height: 32)
    }

    @ViewBuilder
    private var octopusHead: some View {
        if let image = MascotImage.idle {
            Image(nsImage: image)
                .resizable()
                .interpolation(.none)
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 14)
        } else {
            Image(systemName: "fish.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.white)
                .frame(width: 14, height: 14)
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 6, height: 6)
    }

    private var statusColor: Color {
        if viewModel.pendingHookRequest != nil { return .yellow }
        if viewModel.activeSessions > 0 { return .green }
        return .gray.opacity(0.6)
    }
}

// MARK: - Peeking state

private struct PeekingNotchContent: View {
    let viewModel: CoveViewModel
    let namespace: Namespace.ID

    var body: some View {
        VStack(spacing: 0) {
            header
            bodyArea
        }
        .frame(width: 480, height: 220)
    }

    private var header: some View {
        ZStack {
            NotchShape.opened
                .fill(Color.black)
                .matchedGeometryEffect(id: CoveNotchAnimationID.shape, in: namespace)
            HStack(spacing: 8) {
                octopusHead
                    .matchedGeometryEffect(id: CoveNotchAnimationID.octopus, in: namespace)
                Text("Session Cove")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(.white)
                Spacer()
                if viewModel.activeSessions > 0 {
                    activeBadge
                }
            }
            .padding(.horizontal, 14)
        }
        .frame(height: 44)
    }

    private var bodyArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let request = viewModel.pendingHookRequest {
                permissionBadge(request)
            }
            sessionList
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.opacity(0.92))
    }

    private var octopusHead: some View {
        Group {
            if let image = MascotImage.idle {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "fish.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 18, height: 18)
    }

    private var activeBadge: some View {
        HStack(spacing: 3) {
            Circle().fill(.green).frame(width: 5, height: 5)
            Text("\(viewModel.activeSessions)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.green)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(.green.opacity(0.12)))
    }

    private func permissionBadge(_ request: HookPermissionRequest) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Circle().fill(.yellow).frame(width: 6, height: 6).padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text("Permission")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(.yellow.opacity(0.8))
                Text(request.summary)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 4).fill(.yellow.opacity(0.1)))
    }

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("RUNNING")
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
            if rankedIslands.isEmpty {
                Text("No active sessions")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            } else {
                ForEach(rankedIslands) { island in
                    IslandSummaryRow(island: island, compact: true)
                }
            }
        }
    }

    private var rankedIslands: [ProjectIsland] {
        viewModel.islands
            .sorted { lhs, rhs in
                if lhs.activeCount != rhs.activeCount { return lhs.activeCount > rhs.activeCount }
                return lhs.recentCount > rhs.recentCount
            }
            .prefix(3)
            .map { $0 }
    }
}

// MARK: - Opened state

private struct OpenedNotchContent: View {
    let viewModel: CoveViewModel
    let namespace: Namespace.ID

    var body: some View {
        VStack(spacing: 0) {
            header
            bodyArea
        }
        .frame(width: 600, height: 480)
    }

    private var header: some View {
        ZStack {
            NotchShape.opened
                .fill(Color.black)
                .matchedGeometryEffect(id: CoveNotchAnimationID.shape, in: namespace)
            HStack(spacing: 10) {
                octopusHead
                    .matchedGeometryEffect(id: CoveNotchAnimationID.octopus, in: namespace)
                Text("Session Cove")
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    viewModel.notchStatus = .closed
                } label: {
                    Text("×")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 60)
    }

    private var bodyArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("港湾地图（完整态待 PR 5 接入 ProjectIsland）")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 16)
                .padding(.top, 12)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(rankedIslands) { island in
                        IslandSummaryRow(island: island, compact: false)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.opacity(0.92))
    }

    private var octopusHead: some View {
        Group {
            if let image = MascotImage.idle {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "fish.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 22, height: 22)
    }

    private var rankedIslands: [ProjectIsland] {
        viewModel.islands
            .sorted { lhs, rhs in
                if lhs.activeCount != rhs.activeCount { return lhs.activeCount > rhs.activeCount }
                if lhs.recentCount != rhs.recentCount { return lhs.recentCount > rhs.recentCount }
                let lt = lhs.sessions.first?.lastModified ?? .distantPast
                let rt = rhs.sessions.first?.lastModified ?? .distantPast
                return lt > rt
            }
            .prefix(8)
            .map { $0 }
    }
}

// MARK: - Shared row

private struct IslandSummaryRow: View {
    let island: ProjectIsland
    let compact: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(island.activeCount > 0 ? .green : .gray.opacity(0.6))
                .frame(width: compact ? 5 : 6, height: compact ? 5 : 6)
            Text(island.displayName)
                .font(.system(size: compact ? 10 : 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
            Spacer()
            Text("\(island.activeCount)/\(island.totalCount)")
                .font(.system(size: compact ? 9 : 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.vertical, compact ? 2 : 4)
        .padding(.horizontal, compact ? 4 : 8)
        .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(compact ? 0 : 0.04)))
    }
}

// MARK: - Animation IDs

private enum CoveNotchAnimationID {
    static let shape = "notchShape"
    static let octopus = "notchOctopus"
}
