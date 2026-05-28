import SwiftUI

struct CompactBarView: View {
    @Bindable var viewModel: CoveViewModel

    private var hasPendingPermission: Bool {
        viewModel.pendingHookRequest != nil
    }

    private var mascotState: PixelMascotState {
        if hasPendingPermission { return .attention }
        guard let session = viewModel.representativeSession else { return .idle }
        switch session.status {
        case .active: return .working
        case .recentlyIdle: return .idle
        case .archived: return .sleeping
        }
    }

    private var centerText: String {
        if let request = viewModel.pendingHookRequest {
            return "APPROVAL · \(request.toolName.uppercased())"
        }
        if let island = viewModel.representativeIsland, viewModel.activeSessions > 0 {
            return "CODING · \(island.displayName.uppercased())"
        }
        if viewModel.totalSessions > 0 {
            return "\(viewModel.totalSessions) SESSIONS IN COVE"
        }
        return "SESSION COVE"
    }

    private var countText: String {
        if hasPendingPermission { return "!" }
        if viewModel.activeSessions > 0 { return "\(viewModel.activeSessions)" }
        return "\(viewModel.islands.count)"
    }

    var body: some View {
        HStack(spacing: 10) {
            CoveMascotView(state: mascotState, scale: .compact)

            VStack(alignment: .leading, spacing: 1) {
                Text(centerText)
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(PixelPalette.foam.opacity(0.74))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Text(countText)
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(hasPendingPermission ? PixelPalette.ink : .white)
                .frame(width: 24, height: 24)
                .background {
                    PixelBox(
                        fill: hasPendingPermission ? PixelPalette.alert : Color(red: 0.09, green: 0.25, blue: 0.36),
                        edge: hasPendingPermission ? .white.opacity(0.72) : PixelPalette.foam.opacity(0.42)
                    )
                }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: hasPendingPermission
                            ? [Color(red: 0.26, green: 0.22, blue: 0.09), Color(red: 0.08, green: 0.14, blue: 0.22)]
                            : [Color(red: 0.05, green: 0.18, blue: 0.28), Color(red: 0.03, green: 0.08, blue: 0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(Capsule().stroke(hasPendingPermission ? PixelPalette.alert : PixelPalette.foam.opacity(0.30), lineWidth: 1))
                .overlay(alignment: .bottom) {
                    Capsule()
                        .fill(Color.black.opacity(0.22))
                        .offset(y: 2)
                        .mask(Capsule().padding(.top, 20))
                }
        }
        .contentShape(Capsule())
        .onTapGesture {
            viewModel.toggle()
        }
    }

    private var subtitle: String {
        if let request = viewModel.pendingHookRequest {
            let folder = request.projectPath.split(separator: "/").last.map(String.init) ?? "NEEDS DECISION"
            return "\(folder.uppercased()) · ping-card v2"
        }
        if viewModel.activeSessions > 0 {
            return "\(viewModel.activeSessions) ACTIVE · \(viewModel.islands.count) ISLANDS"
        }
        return "\(viewModel.islands.count) ISLANDS · \(viewModel.totalSessions) TOTAL"
    }
}
