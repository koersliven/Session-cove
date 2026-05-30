import SwiftUI

/// The visual content displayed inside a Notch-mode panel.
/// PR 3 implements only the `closed` state: NotchShape + tiny octopus head + status dot.
/// PR 4 will introduce peeking/opened variants and animation transitions.
///
/// Frame is hardcoded to 224×32 to match `ScreenNotchMetrics.fallback` (PR 3.F, parallel).
/// Once PR 3.F lands, this can switch to `ScreenNotchMetrics.fallback.size` to stay in sync.
struct CoveNotchView: View {
    @Bindable var viewModel: CoveViewModel

    var body: some View {
        ZStack {
            NotchShape.closed
                .fill(Color.black)
            HStack(spacing: 4) {
                octopusHead
                statusDot
            }
            .padding(.horizontal, 8)
        }
        .frame(width: 224, height: 32)
    }

    @ViewBuilder
    private var octopusHead: some View {
        if let image = MascotImage.idle {
            Image(nsImage: image)
                .resizable()
                .interpolation(.none)
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 14)
        } else {
            Image(systemName: "fish.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.white)
                .frame(width: 14, height: 14)
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 6, height: 6)
    }

    private var statusColor: Color {
        // PR 4 will replace this with a proper NotchStatus enum on the view model.
        if viewModel.pendingHookRequest != nil {
            return .yellow
        }
        if viewModel.activeSessions > 0 {
            return .green
        }
        return .gray.opacity(0.6)
    }
}
