import SwiftUI

/// Toast card shown when a Claude session finishes a turn (Stop hook).
/// Same 388pt-wide envelope as `PermissionPingCard` but taller (120pt) and
/// distinguished by a cyan-mint stroke instead of the alert-yellow used by
/// the permission strip — quick visual read of "task done" vs "approve me".
///
/// Buttons:
///  - 知道了 (`.acknowledge`): just dismisses the toast.
///  - 打开 session (`.openSession`): resumes the related SessionRecord, or
///    falls back to launching a new session in the project when the
///    SessionScanner hasn't yet ingested the just-finished JSONL.
///
/// Auto-dismiss after 30s lives in `CoveViewModel.updatePendingHookRequest`,
/// not here, because the timer must survive across SwiftUI view re-creates.
struct CompletionPingCard: View {
    let request: HookPermissionRequest
    let resolvedSession: SessionRecord?
    let onDecision: (HookApprovalDecision) -> Void

    private var sessionLabel: String {
        if let resolved = resolvedSession { return resolved.displayTitle }
        if let sid = request.sessionId, !sid.isEmpty {
            return "Session " + sid.prefix(8)
        }
        return "Session"
    }

    private var projectName: String {
        let last = (request.projectPath as NSString).lastPathComponent
        return last.isEmpty ? request.projectPath : last
    }

    private var canOpenSession: Bool {
        // We can always launchNew given a non-empty projectPath; the button
        // only collapses when both are missing (unlikely for real Stop events).
        if let sid = request.sessionId, !sid.isEmpty { return true }
        return !request.projectPath.isEmpty
    }

    var body: some View {
        // Pull title from provider.ui — today every provider's
        // completionTitle is "任务完成", but the indirection lets us localize
        // per provider later (e.g. "Cursor 完成回合") without touching the view.
        // SwiftUI body renders on main; assumeIsolated mirrors the existing
        // ProcessDetector pattern for hopping into the @MainActor registry.
        let provider = MainActor.assumeIsolated {
            AgentProviderRegistry.shared.provider(for: request)
        }
        return HStack(spacing: 10) {
            CoveMascotView(state: .idle, scale: .row)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(provider.ui.completionTitle)
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundStyle(.white)

                Text(sessionLabel)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)

                Text(projectName)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            .frame(maxWidth: 200, alignment: .leading)

            Spacer(minLength: 4)

            HStack(spacing: 5) {
                button(.acknowledge, style: .quiet)
                if canOpenSession {
                    button(.openSession, style: .blue)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.04, green: 0.10, blue: 0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(PixelPalette.foam.opacity(0.32), lineWidth: 1)
                )
        )
    }

    private func button(_ decision: HookApprovalDecision, style: CompletionButtonStyle) -> some View {
        Button {
            onDecision(decision)
        } label: {
            Text(decision.title)
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(style.foreground)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
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

private enum CompletionButtonStyle {
    case quiet, blue

    var foreground: Color {
        switch self {
        case .quiet: .white.opacity(0.64)
        case .blue: .white.opacity(0.92)
        }
    }

    var background: Color {
        switch self {
        case .quiet: .white.opacity(0.10)
        case .blue: Color(red: 0.12, green: 0.44, blue: 0.85).opacity(0.86)
        }
    }

    var borderOpacity: Double {
        switch self {
        case .quiet: 0.12
        case .blue: 0.18
        }
    }
}
