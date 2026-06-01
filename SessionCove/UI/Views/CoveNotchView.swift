import SwiftUI

/// Visual content of the Notch panel. The hosting NSPanel is constant size
/// (full screen width × 750pt) and never resizes — all morphing happens inside
/// `morphingNotch`, a black clipped container whose frame + corner radii
/// animate across states.
///
/// Design (mirrors ping-island's NotchView):
/// - One `AdaptiveHeader` instance handles all states (closed/peeking/opened)
///   so SwiftUI doesn't unmount/remount the header subtree on transitions.
/// - One `HarborMapOverviewView` instance is shared between peeking + opened
///   via the `compact` parameter. Without this sharing, `peeking → opened`
///   tore down ~6 islands × ~3 Timers + multiple `.repeatForever` springs and
///   rebuilt them, causing the visible "卡顿" lag the user reported.
struct CoveNotchView: View {
    @Bindable var viewModel: CoveViewModel

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            morphingNotch
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var morphingNotch: some View {
        VStack(spacing: 0) {
            AdaptiveHeader(viewModel: viewModel)

            if viewModel.notchStatus != .closed {
                HarborMapOverviewView(
                    viewModel: viewModel,
                    showsHeader: false,
                    compact: viewModel.notchStatus == .peeking,
                    onAnyIslandTap: viewModel.notchStatus == .peeking
                        ? { viewModel.notchStatus = .opened }
                        : nil
                )
                // Pure opacity transition for body — anything heavier (scale,
                // matchedGeometry) compounded with the outer spring animation
                // visibly stuttered the harbor on insertion. Outgoing fade is
                // fast so it doesn't drag during the new state's reveal.
                .transition(.asymmetric(
                    insertion: .opacity.animation(.easeOut(duration: 0.22)),
                    removal: .opacity.animation(.easeIn(duration: 0.12))
                ))
            }
        }
        .frame(width: notchWidth, height: notchHeight, alignment: .top)
        .background(Color.black)
        .clipShape(NotchShape(topRadius: topRadius, bottomRadius: bottomRadius))
        .animation(.spring(response: 0.42, dampingFraction: 0.92), value: viewModel.notchStatus)
    }

    private var notchWidth: CGFloat {
        switch viewModel.notchStatus {
        case .closed: return 224
        case .peeking: return 480
        case .opened, .popping: return 600
        }
    }

    private var notchHeight: CGFloat {
        switch viewModel.notchStatus {
        case .closed: return 32
        case .peeking: return 220
        case .opened, .popping: return 480
        }
    }

    private var topRadius: CGFloat {
        switch viewModel.notchStatus {
        case .closed: return 6
        case .peeking: return 14
        case .opened, .popping: return 19
        }
    }

    private var bottomRadius: CGFloat {
        switch viewModel.notchStatus {
        case .closed: return 14
        case .peeking: return 22
        case .opened, .popping: return 24
        }
    }
}

// MARK: - Adaptive Header
//
// One struct, three visual modes. Single SwiftUI identity means the octopus
// image, status dot, etc. don't unmount across state transitions — only their
// frame/padding/visibility change, all of which the outer .animation(_, value:)
// interpolates smoothly.

private struct AdaptiveHeader: View {
    @Bindable var viewModel: CoveViewModel

    var body: some View {
        HStack(spacing: spacing) {
            octopusHead

            if !isClosed {
                Text("Session Cove")
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundStyle(.white)
            }

            if isClosed {
                statusDot
            }

            Spacer(minLength: 0)

            if viewModel.notchStatus == .peeking, viewModel.activeSessions > 0 {
                activeBadge
            }

            if viewModel.notchStatus == .opened || viewModel.notchStatus == .popping {
                closeButton
            }
        }
        .padding(.horizontal, horizontalPadding)
        .frame(height: height)
        .contentShape(Rectangle())
        .onTapGesture {
            switch viewModel.notchStatus {
            case .closed, .peeking:
                viewModel.notchStatus = .opened
            default:
                break
            }
        }
    }

    private var isClosed: Bool { viewModel.notchStatus == .closed }
    private var spacing: CGFloat { isClosed ? 4 : 10 }
    private var horizontalPadding: CGFloat { isClosed ? 8 : 16 }
    private var height: CGFloat { isClosed ? 32 : 60 }
    private var octopusSize: CGFloat { isClosed ? 14 : 22 }

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
        .frame(width: octopusSize, height: octopusSize)
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

    private var closeButton: some View {
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
}
