import SwiftUI

struct SessionDetailView: View {
    let session: SessionRecord
    @Bindable var viewModel: CoveViewModel

    private var hasPendingPermission: Bool {
        guard let req = viewModel.pendingHookRequest else { return false }
        return req.projectPath == session.projectPath
    }

    var body: some View {
        ZStack {
            PixelOceanBackground()
            VStack(spacing: 0) {
                cabinHeader
                cabinBody
            }
        }
    }

    // MARK: - Cabin Header

    private var cabinHeader: some View {
        HStack(spacing: 0) {
            pixelNavButton("< BACK") { viewModel.back() }

            Spacer()

            PixelHUDPanel {
                HStack(spacing: 6) {
                    statusIndicator
                    Text(statusLabel)
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundStyle(.white)
                }
            }

            Spacer()

            pixelNavButton("X") { viewModel.closeToCompact() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Cabin Body (Agent Room)

    private var cabinBody: some View {
        ScrollView {
            VStack(spacing: 14) {
                agentAvatar
                captainLog
                if hasPendingPermission, let request = viewModel.pendingHookRequest {
                    permissionHUD(request)
                }
                actionDock
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Agent Avatar

    private var agentAvatar: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(PixelPalette.hud.opacity(0.44))
                .frame(height: 120)

            HStack(spacing: 16) {
                ZStack {
                    if hasPendingPermission {
                        PixelAttentionRing()
                            .frame(width: 96, height: 96)
                    }

                    AnimatedMascot(
                        active: session.status == .active,
                        archived: session.status == .archived,
                        size: 72
                    )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.displayTitle.uppercased())
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Text(projectName.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(PixelPalette.foam.opacity(0.84))
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        statusIndicator
                        Text(stateDescription)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(stateColor.opacity(0.9))
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Captain Log (metadata)

    private var captainLog: some View {
        PixelHUDPanel {
            VStack(alignment: .leading, spacing: 6) {
                logHeader

                logRow(icon: "ID", value: session.id)
                logRow(icon: "DIR", value: session.projectPath)
                logRow(icon: "TIME", value: session.relativeTime)
                if let branch = session.gitBranch {
                    logRow(icon: "GIT", value: branch)
                }
                if let version = session.version {
                    logRow(icon: "VER", value: "v\(version)")
                }
            }
        }
    }

    private var logHeader: some View {
        HStack(spacing: 6) {
            Rectangle().fill(PixelPalette.foam.opacity(0.62)).frame(width: 3, height: 12)
            Text("CAPTAIN LOG")
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundStyle(PixelPalette.foam.opacity(0.72))
            Spacer()
        }
    }

    private func logRow(icon: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(icon)
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundStyle(PixelPalette.foam.opacity(0.52))
                .frame(width: 28, alignment: .trailing)
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(2)
                .textSelection(.enabled)
            Spacer()
        }
    }

    // MARK: - Permission HUD (inline when session has pending request)

    private func permissionHUD(_ request: HookPermissionRequest) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Rectangle().fill(PixelPalette.alert).frame(width: 3, height: 12)
                Text("APPROVAL REQUIRED")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundStyle(PixelPalette.alert)
                Spacer()
            }

            HookApprovalPanel(request: request) { decision in
                viewModel.decideHookRequest(decision)
            }
        }
    }

    // MARK: - Action Dock

    private var actionDock: some View {
        HStack(spacing: 10) {
            actionButton(
                label: session.status == .active ? "OPEN TERMINAL" : "RESUME",
                icon: session.status == .active ? "arrow.uturn.forward" : "play.fill",
                style: .primary
            ) {
                viewModel.resumeSession(session)
            }
        }
    }

    // MARK: - Helpers

    private var projectName: String {
        let path = session.projectPath
        return (path as NSString).lastPathComponent
    }

    private var statusLabel: String {
        if hasPendingPermission { return "ATTENTION" }
        switch session.status {
        case .active: return "WORKING"
        case .recentlyIdle: return "IDLE"
        case .archived: return "SLEEPING"
        }
    }

    private var stateDescription: String {
        if hasPendingPermission { return "AWAITING DECISION" }
        switch session.status {
        case .active: return "CODING IN PROGRESS"
        case .recentlyIdle: return "RECENTLY ACTIVE"
        case .archived: return "DORMANT"
        }
    }

    private var stateColor: Color {
        if hasPendingPermission { return PixelPalette.alert }
        switch session.status {
        case .active: return PixelPalette.grass
        case .recentlyIdle: return PixelPalette.sand
        case .archived: return Color(red: 0.50, green: 0.49, blue: 0.42)
        }
    }

    private var statusIndicator: some View {
        Rectangle()
            .fill(stateColor)
            .frame(width: 8, height: 8)
    }

    private func pixelNavButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background { PixelBox(fill: PixelPalette.hud.opacity(0.90), edge: PixelPalette.hudEdge) }
        }
        .buttonStyle(.plain)
    }

    private func actionButton(label: String, icon: String, style: ActionStyle, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                Text(label)
                    .font(.system(size: 11, weight: .black, design: .monospaced))
            }
            .foregroundStyle(style == .primary ? PixelPalette.ink : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background {
                PixelBox(
                    fill: style == .primary ? PixelPalette.foam.opacity(0.92) : PixelPalette.hud.opacity(0.80),
                    edge: style == .primary ? PixelPalette.foam : PixelPalette.hudEdge
                )
            }
        }
        .buttonStyle(.plain)
    }

    private enum ActionStyle {
        case primary
        case secondary
    }
}
