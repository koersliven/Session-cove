import SwiftUI

struct ProjectIslandShelfView: View {
    let island: ProjectIsland
    var hasPendingPermission: Bool = false
    let onProjectTap: () -> Void
    let onSessionTap: (SessionRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            shelfContent
        }
        .background(shelfBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var shelfContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            projectRow
            if !recentSessions.isEmpty {
                sessionsArea
            }
        }
    }

    private var projectRow: some View {
        Button(action: onProjectTap) {
            HStack(spacing: 10) {
                CoveMascotView(state: mascotState, scale: .shelf, grounded: true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(island.displayName)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(projectSubtitle)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }

                Spacer()

                if hasPendingPermission {
                    PermissionBeacon()
                }

                CrewCountBuoy(count: island.totalCount, isActive: island.activeCount > 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var sessionsArea: some View {
        VStack(spacing: 1) {
            ForEach(recentSessions) { session in
                SessionPebbleRow(
                    session: session,
                    isAttention: pendingSessionIDs.contains(session.id),
                    onTap: { onSessionTap(session) }
                )
            }
        }
        .padding(.leading, 56)
        .padding(.trailing, 8)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var shelfBackground: some View {
        ZStack {
            IslandShelfShape(mood: islandMood)
            // Subtle state-based accent glow at top
            VStack {
                Rectangle()
                    .fill(stateAccent.opacity(0.08))
                    .frame(height: 3)
                Spacer()
            }
        }
    }

    // MARK: - Computed

    private var recentSessions: [SessionRecord] {
        island.sessions
            .sorted { $0.lastModified > $1.lastModified }
            .prefix(3)
            .map { $0 }
    }

    private var pendingSessionIDs: Set<String> {
        guard hasPendingPermission, let first = recentSessions.first else { return [] }
        return [first.id]
    }

    private var mascotState: PixelMascotState {
        if hasPendingPermission { return .attention }
        if island.activeCount > 0 { return .working }
        if island.recentCount > 0 { return .idle }
        return .sleeping
    }

    private var islandMood: IslandMood {
        if island.activeCount > 0 { return .active }
        if island.recentCount > 0 { return .recent }
        return .archived
    }

    private var stateAccent: Color {
        switch mascotState {
        case .working: PixelPalette.grass
        case .attention: PixelPalette.alert
        case .idle: PixelPalette.sand
        case .sleeping, .dragged: .clear
        }
    }

    private var projectSubtitle: String {
        let folder = island.path.split(separator: "/").last.map(String.init) ?? island.path
        return "\(folder) · \(island.totalCount) sessions"
    }
}
