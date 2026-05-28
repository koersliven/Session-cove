import SwiftUI

struct HookApprovalPanel: View {
    let request: HookPermissionRequest
    let onDecision: (HookApprovalDecision) -> Void

    var body: some View {
        PixelHUDPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    CoveMascotView(state: .attention, scale: .approval)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Permission Request")
                            .font(.system(size: 13, weight: .black, design: .monospaced))
                            .foregroundStyle(.white)
                        Text(request.toolName)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.yellow)
                    }
                    Spacer()
                }

                Text(request.summary)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.76))
                    .lineLimit(3)

                Text(request.projectPath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(1)

                HStack(spacing: 7) {
                    decisionButton(.deny, style: .quiet)
                    Spacer(minLength: 0)
                    decisionButton(.allowSession, style: .blue)
                    decisionButton(.alwaysAllow, style: .blue)
                    decisionButton(.allow, style: .primary)
                }
            }
        }
        .frame(width: 320)
    }

    private func decisionButton(_ decision: HookApprovalDecision, style: DecisionButtonStyle) -> some View {
        Button {
            onDecision(decision)
        } label: {
            Text(decision.title)
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(style.foreground)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(style.background)
                        .overlay(Capsule().stroke(.white.opacity(style.borderOpacity), lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
        .help(decision.detail)
    }
}

private enum DecisionButtonStyle {
    case quiet
    case blue
    case primary

    var foreground: Color {
        switch self {
        case .quiet: .white.opacity(0.64)
        case .blue: .white.opacity(0.9)
        case .primary: Color(red: 0.04, green: 0.13, blue: 0.20)
        }
    }

    var background: Color {
        switch self {
        case .quiet: .white.opacity(0.10)
        case .blue: Color(red: 0.12, green: 0.44, blue: 0.85).opacity(0.86)
        case .primary: .white.opacity(0.92)
        }
    }

    var borderOpacity: Double {
        switch self {
        case .quiet: 0.12
        case .blue: 0.18
        case .primary: 0.42
        }
    }
}
