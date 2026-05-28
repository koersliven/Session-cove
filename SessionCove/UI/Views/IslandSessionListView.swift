import SwiftUI

struct IslandSessionListView: View {
    let island: ProjectIsland
    @Bindable var viewModel: CoveViewModel
    @State private var hoveredSessionID: String?

    private var displayedIsland: ProjectIsland {
        viewModel.islands.first { $0.id == island.id } ?? island
    }

    private var sortedSessions: [SessionRecord] {
        displayedIsland.sessions.sorted { $0.lastModified > $1.lastModified }
    }

    private var featuredSessions: [SessionRecord] {
        sortedSessions.sorted { lhs, rhs in
            if lhs.status != rhs.status {
                return statusRank(lhs.status) < statusRank(rhs.status)
            }
            return lhs.lastModified > rhs.lastModified
        }
    }

    var body: some View {
        ZStack {
            PixelOceanBackground()
            VStack(spacing: 0) {
                header
                projectBase
                sessionDock
            }
        }
    }

    private var header: some View {
        HStack {
            pixelButton("< MAP") { viewModel.back() }
            PixelHUDPanel {
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayedIsland.displayName.uppercased())
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .foregroundStyle(.white)
                    Text("PROJECT BASE / \(displayedIsland.totalCount) CREW SLOTS")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundStyle(PixelPalette.foam.opacity(0.84))
                }
            }
            Spacer()
            PixelHUDPanel {
                HStack(spacing: 12) {
                    stat("ON", displayedIsland.activeCount, PixelPalette.grass)
                    stat("ID", displayedIsland.recentCount, PixelPalette.sand)
                    stat("ALL", displayedIsland.totalCount, .white.opacity(0.78))
                }
            }
        }
        .padding(12)
    }

    private var projectBase: some View {
        GeometryReader { geo in
            ZStack {
                PixelBaseWaterMarks(size: geo.size)

                let islandFrame = baseIslandFrame(in: geo.size)
                PixelIslandSprite(mood: baseMood)
                    .frame(width: islandFrame.width, height: islandFrame.height)
                    .position(x: islandFrame.midX, y: islandFrame.midY)

                ForEach(Array(featuredSessions.prefix(3).enumerated()), id: \.element.id) { index, session in
                    let anchor = mascotAnchor(index: index, in: islandFrame)
                    sessionMascot(session, index: index)
                        .position(x: anchor.x, y: anchor.y)
                        .zIndex(anchor.y)
                        .onTapGesture { viewModel.selectSession(session) }
                }

                if sortedSessions.count > featuredSessions.count {
                    dockedCrewBadge(sortedSessions.count - featuredSessions.count)
                        .position(x: islandFrame.maxX - 110, y: islandFrame.maxY - 34)
                }

                if let request = viewModel.pendingHookRequest, request.projectPath == displayedIsland.path {
                    approvalFlag(request)
                        .position(x: geo.size.width * 0.67, y: geo.size.height * 0.22)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var sessionDock: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sortedSessions) { session in
                    sessionCard(session)
                        .onHover { hovered in
                            hoveredSessionID = hovered ? session.id : (hoveredSessionID == session.id ? nil : hoveredSessionID)
                        }
                        .onTapGesture { viewModel.selectSession(session) }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(PixelPalette.ink.opacity(0.24))
    }

    private var baseMood: IslandMood {
        if displayedIsland.activeCount > 0 { return .active }
        if displayedIsland.recentCount > 0 { return .recent }
        return .archived
    }

    private func sessionMascot(_ session: SessionRecord, index: Int) -> some View {
        let isHovered = hoveredSessionID == session.id
        let hasPending = viewModel.pendingHookRequest?.projectPath == displayedIsland.path && index == 0
        return ZStack(alignment: .top) {
            if isHovered || hasPending {
                Rectangle()
                    .fill(hasPending ? PixelPalette.alert : PixelPalette.foam)
                    .frame(width: 32, height: 5)
                    .offset(y: -8)
            }
            GroundedMascot(
                active: session.status == .active,
                archived: session.status == .archived,
                size: isHovered ? 60 : 48,
                stateOverride: hasPending || isHovered ? .attention : nil,
                facingLeft: index.isMultiple(of: 2)
            )
        }
        .frame(width: 74, height: 74)
        .animation(.snappy(duration: 0.16), value: isHovered)
        .animation(.snappy(duration: 0.16), value: hasPending)
    }

    private func sessionCard(_ session: SessionRecord) -> some View {
        let isHovered = hoveredSessionID == session.id
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                PixelOctopusSprite(state: isHovered ? .attention : mascotState(for: session))
                    .frame(width: 34, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(statusLabel(for: session))
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundStyle(statusColor(for: session))
                    Text(session.relativeTime.uppercased())
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.52))
                }
            }

            Text(session.displayTitle)
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(2)
                .frame(height: 28, alignment: .topLeading)

            HStack {
                if let branch = session.gitBranch {
                    Text(branch.uppercased())
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundStyle(PixelPalette.foam.opacity(0.70))
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    viewModel.resumeSession(session)
                } label: {
                    Text(session.status == .active ? "OPEN" : "GO")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background { PixelBox(fill: Color(red: 0.12, green: 0.24, blue: 0.34), edge: PixelPalette.foam.opacity(0.58)) }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .frame(width: 188, height: 112)
        .background {
            PixelBox(
                fill: isHovered ? Color(red: 0.08, green: 0.17, blue: 0.24) : PixelPalette.hud.opacity(0.88),
                edge: isHovered ? PixelPalette.alert : PixelPalette.hudEdge.opacity(0.82)
            )
        }
    }

    private func approvalFlag(_ request: HookPermissionRequest) -> some View {
        PixelHUDPanel {
            HStack(spacing: 7) {
                PixelOctopusSprite(state: .attention).frame(width: 30, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text("APPROVAL")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundStyle(PixelPalette.alert)
                    Text(request.toolName.uppercased())
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.86))
                }
            }
        }
    }

    private func baseIslandFrame(in size: CGSize) -> CGRect {
        let width = min(size.width * 0.72, 820)
        let height = min(size.height * 0.50, 320)
        return CGRect(
            x: size.width * 0.50 - width / 2,
            y: size.height * 0.54 - height / 2,
            width: width,
            height: height
        )
    }

    private func mascotAnchor(index: Int, in islandFrame: CGRect) -> CGPoint {
        let anchors = [
            CGPoint(x: 0.50, y: 0.68),
            CGPoint(x: 0.38, y: 0.73),
            CGPoint(x: 0.62, y: 0.73)
        ]
        let anchor = anchors[index % anchors.count]
        return CGPoint(
            x: islandFrame.minX + islandFrame.width * anchor.x,
            y: islandFrame.minY + islandFrame.height * anchor.y
        )
    }

    private func dockedCrewBadge(_ hiddenCount: Int) -> some View {
        PixelHUDPanel {
            HStack(spacing: 6) {
                Rectangle()
                    .fill(PixelPalette.foam.opacity(0.72))
                    .frame(width: 8, height: 8)
                Text("+\(hiddenCount) AT DOCK")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.88))
            }
        }
    }

    private func stat(_ label: String, _ value: Int, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 8, weight: .black, design: .monospaced)).foregroundStyle(.white.opacity(0.64))
            Text("\(value)").font(.system(size: 10, weight: .black, design: .monospaced)).foregroundStyle(color)
        }
    }

    private func pixelButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background { PixelBox(fill: PixelPalette.hud.opacity(0.90), edge: PixelPalette.hudEdge) }
        }
        .buttonStyle(.plain)
    }

    private func statusRank(_ status: SessionStatus) -> Int {
        switch status {
        case .active: 0
        case .recentlyIdle: 1
        case .archived: 2
        }
    }

    private func mascotState(for session: SessionRecord) -> PixelMascotState {
        switch session.status {
        case .active: .working
        case .recentlyIdle: .idle
        case .archived: .sleeping
        }
    }

    private func statusLabel(for session: SessionRecord) -> String {
        switch session.status {
        case .active: "CODING"
        case .recentlyIdle: "IDLE"
        case .archived: "SLEEP"
        }
    }

    private func statusColor(for session: SessionRecord) -> Color {
        switch session.status {
        case .active: PixelPalette.grass
        case .recentlyIdle: PixelPalette.sandLight
        case .archived: .white.opacity(0.58)
        }
    }
}

private struct PixelBaseWaterMarks: View {
    let size: CGSize

    var body: some View {
        Canvas { context, _ in
            let unit: CGFloat = 8
            let marks = [
                CGPoint(x: size.width * 0.18, y: size.height * 0.22),
                CGPoint(x: size.width * 0.78, y: size.height * 0.28),
                CGPoint(x: size.width * 0.20, y: size.height * 0.72),
                CGPoint(x: size.width * 0.82, y: size.height * 0.68),
                CGPoint(x: size.width * 0.50, y: size.height * 0.18),
                CGPoint(x: size.width * 0.50, y: size.height * 0.82)
            ]
            for mark in marks {
                context.fill(Path(CGRect(x: floor(mark.x / unit) * unit, y: floor(mark.y / unit) * unit, width: unit * 3, height: unit)), with: .color(PixelPalette.foam.opacity(0.46)))
            }
        }
        .allowsHitTesting(false)
    }
}
