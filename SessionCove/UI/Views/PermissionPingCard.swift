import SwiftUI

struct PermissionPingCard: View {
    let request: HookPermissionRequest
    @Binding var isExpanded: Bool
    let onDecision: (HookApprovalDecision) -> Void

    /// Chevron only renders when there's something to expand. Legacy v2
    /// payloads (no `toolInputJSON`) still surface the original 72pt strip
    /// untouched — collapsed view is identical to the pre-feature behavior.
    private var hasExpandableDetail: Bool {
        if let json = request.toolInputJSON, !json.isEmpty { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 6) {
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

                if hasExpandableDetail {
                    chevronButton
                }

                Spacer(minLength: 4)

                HStack(spacing: 5) {
                    pingButton(.deny, style: .quiet)
                    pingButton(.alwaysAllow, style: .primary)
                    pingButton(.allow, style: .blue)
                }
            }

            if isExpanded, hasExpandableDetail {
                detailPanel
                    .transition(.opacity)
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

    /// Detail toggle. Renders as a small `(i) 详情` capsule with a
    /// chevron that flips on expand — much clearer affordance than a bare
    /// `>` glyph. The capsule background gets stronger when expanded so
    /// the active state is visible from a glance. Help text exposes the
    /// shortcut hint to VoiceOver / hover tooltips.
    private var chevronButton: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "info.circle")
                    .font(.system(size: 9, weight: .semibold))
                Text("详情")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .black))
            }
            .foregroundStyle(isExpanded ? PixelPalette.alert : .white.opacity(0.78))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .background(
                Capsule()
                    .fill(isExpanded ? PixelPalette.alert.opacity(0.18) : .white.opacity(0.10))
                    .overlay(
                        Capsule()
                            .stroke(
                                isExpanded ? PixelPalette.alert.opacity(0.55) : .white.opacity(0.16),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .help(isExpanded ? "收起详情" : "查看完整 tool_input")
    }

    /// Detail panel rendered when `isExpanded`. Single Text node inside a
    /// ScrollView — never ForEach over lines — so SwiftUI's text shaper
    /// handles wrapping in one pass even on 8KB content. lineLimit(nil) +
    /// textSelection so the user can copy commands or paths verbatim.
    private var detailPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("TOOL INPUT")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundStyle(PixelPalette.alert)
                Spacer()
                if request.toolInputTruncated {
                    Text("truncated 8KB")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.42))
                }
            }

            ScrollView(.vertical, showsIndicators: true) {
                Text(detailText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.86))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(nil)
                    .textSelection(.enabled)
                    .padding(.vertical, 2)
            }
            .frame(maxHeight: 132)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    /// Format the detail panel content per tool. Bash gets a `$ <command>`
    /// prefix using `matchValue` (already full-length); Read/Write/Edit
    /// surface file_path + the JSON body so the user can see the planned
    /// content/diff. Anything else falls through to the raw JSON.
    private var detailText: String {
        let json = request.toolInputJSON ?? ""
        switch request.toolName {
        case "Bash":
            if !request.matchValue.isEmpty {
                return "$ " + request.matchValue
            }
            return json
        case "Read", "Write", "Edit", "MultiEdit":
            if !request.matchValue.isEmpty {
                return "file: \(request.matchValue)\n\n\(json)"
            }
            return json
        default:
            return json
        }
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
