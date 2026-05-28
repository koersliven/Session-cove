import SwiftUI

/// DEPRECATED — do NOT use as the default permission route.
///
/// This view was the original full-screen permission interruption scene with
/// PixelOceanBackground, large island, attention ring, and full HookApprovalPanel.
/// It has been replaced by `PermissionPingCard` routed through `.ping` frame size.
///
/// Keep this file only for reference / debug / potential future map-mode revival.
/// If re-enabling, add a dedicated opt-in flag (e.g. `#if DEBUG_LEGACY_PERMISSION_SCENE`)
/// and never connect it to the default `.permissionInterruption` route.
struct LegacyPermissionInterruptionView: View {
    @Bindable var viewModel: CoveViewModel

    private var request: HookPermissionRequest? {
        viewModel.pendingHookRequest
    }

    private var island: ProjectIsland? {
        viewModel.attentionIsland ?? viewModel.selectedIsland
    }

    private var session: SessionRecord? {
        viewModel.selectedSession ?? island?.sessions.sorted { $0.lastModified > $1.lastModified }.first
    }

    var body: some View {
        ZStack {
            PixelOceanBackground()
            VStack(spacing: 0) {
                header
                Spacer(minLength: 8)
                interruptionStage
                Spacer(minLength: 8)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            pixelButton("< COVE") { viewModel.back() }
            Spacer()
            PixelHUDPanel {
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(PixelPalette.alert)
                        .frame(width: 10, height: 10)
                    Text("PERMISSION SIGNAL")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundStyle(.white)
                }
            }
            pixelButton("X") { viewModel.closeToCompact() }
        }
        .padding(12)
    }

    // MARK: - Stage

    private var interruptionStage: some View {
        HStack(alignment: .top, spacing: 16) {
            contextColumn
                .frame(maxWidth: .infinity)

            decisionColumn
                .frame(width: 340)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Left: Context Column

    private var contextColumn: some View {
        VStack(spacing: 12) {
            ZStack {
                PixelAttentionRing()
                    .frame(width: 440, height: 230)
                    .opacity(request == nil ? 0.32 : 1)

                PixelIslandSprite(mood: .active)
                    .frame(width: 420, height: 208)
                    .offset(y: 14)

                GroundedMascot(
                    active: true,
                    archived: false,
                    size: 64,
                    stateOverride: .attention,
                    facingLeft: false
                )
                .position(x: 220, y: 132)
            }
            .frame(width: 460, height: 244)

            PixelHUDPanel {
                VStack(alignment: .leading, spacing: 4) {
                    Text((island?.displayName ?? "UNKNOWN PROJECT").uppercased())
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if let session {
                        Text(session.displayTitle.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(PixelPalette.foam.opacity(0.84))
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: 340)

            if let session {
                pixelButton(session.status == .active ? "OPEN ACTIVE SESSION" : "RESUME SESSION") {
                    viewModel.resumeSession(session)
                }
            }
        }
    }

    // MARK: - Right: Decision Column

    private var decisionColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let request {
                requestContext(request)
                HookApprovalPanel(request: request) { decision in
                    viewModel.decideHookRequest(decision)
                }
            } else {
                PixelHUDPanel {
                    VStack(spacing: 6) {
                        Text("NO PENDING REQUEST")
                            .font(.system(size: 12, weight: .black, design: .monospaced))
                            .foregroundStyle(.white)
                        Text("ALL CLEAR")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(PixelPalette.foam.opacity(0.62))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func requestContext(_ request: HookPermissionRequest) -> some View {
        PixelHUDPanel {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Rectangle().fill(PixelPalette.alert).frame(width: 3, height: 12)
                    Text("REQUEST DETAIL")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundStyle(PixelPalette.alert.opacity(0.9))
                    Spacer()
                }

                contextRow("TOOL", request.toolName)
                contextRow("PATH", request.projectPath)
                contextRow("INFO", request.summary)
            }
        }
    }

    private func contextRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundStyle(PixelPalette.foam.opacity(0.52))
                .frame(width: 32, alignment: .trailing)
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(3)
            Spacer()
        }
    }

    // MARK: - Pixel Button

    private func pixelButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background { PixelBox(fill: Color(red: 0.12, green: 0.24, blue: 0.34), edge: PixelPalette.foam.opacity(0.58)) }
        }
        .buttonStyle(.plain)
    }
}
