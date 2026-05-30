import SwiftUI

struct PermissionPingCard: View {
    let request: HookPermissionRequest
    let onDecision: (HookApprovalDecision) -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(request.toolName.uppercased())
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(.white)

                Text(request.summary)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.64))
                    .lineLimit(1)
            }
            .frame(maxWidth: 120, alignment: .leading)

            Spacer(minLength: 4)

            HStack(spacing: 5) {
                pingButton(.deny, style: .quiet)
                pingButton(.alwaysAllow, style: .primary)
                pingButton(.allow, style: .blue)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.04, green: 0.10, blue: 0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(PixelPalette.alert.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private func pingButton(_ decision: HookApprovalDecision, style: PingButtonStyle) -> some View {
        Button {
            onDecision(decision)
        } label: {
            Text(decision.title)
                .font(.system(size: style == .primary ? 11 : 10, weight: .black, design: .monospaced))
                .foregroundStyle(style.foreground)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, style == .primary ? 14 : 10)
                .padding(.vertical, style == .primary ? 7 : 6)
                .contentShape(Rectangle())
                .background(
                    Capsule()
                        .fill(style.background)
                        .overlay(Capsule().stroke(.white.opacity(style.borderOpacity), lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
    }
}

private enum PingButtonStyle {
    case quiet, blue, primary

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
