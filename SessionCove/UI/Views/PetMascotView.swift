import SwiftUI

struct PetMascotView: View {
    @Bindable var viewModel: CoveViewModel
    @State private var isDragging = false

    private var mascotState: PixelMascotState {
        if isDragging { return .dragged }
        if viewModel.pendingHookRequest != nil { return .attention }
        // The body block reads `mascotState` THREE times per frame (state
        // input, vertical offset, breath scale). Resolving via
        // `representativeSession` re-sorts islands + sessions on every read
        // — at 30fps that was 180 sort calls/s, hot enough on the main
        // thread to make the pet panel's mouse-event dispatch feel frozen.
        // Aggregate counts on the view model are O(islands), no sort.
        if viewModel.activeSessions > 0 { return .working }
        if viewModel.islands.contains(where: { $0.recentCount > 0 }) { return .idle }
        if viewModel.islands.isEmpty { return .idle }
        return .sleeping
    }

    private var hasAttention: Bool {
        viewModel.pendingHookRequest != nil
    }

    private var animationInterval: TimeInterval {
        switch mascotState {
        case .working, .attention: 1.0 / 30.0
        default: 1.0 / 10.0
        }
    }

    var body: some View {
        ZStack {
            PetInteractionView(
                onTap: { viewModel.toggle() },
                onDragStart: { isDragging = true },
                onDragUpdate: { _ in },
                onDragEnd: {
                    isDragging = false
                    viewModel.petDragEnded()
                }
            )

            TimelineView(.animation(minimumInterval: animationInterval)) { timeline in
                // Compute once per frame — `mascotState` is read by the
                // mascot view, the vertical offset, and the breath scale.
                // Re-reading it three times re-resolves all the model
                // queries every frame for no reason.
                let state = mascotState
                let time = timeline.date.timeIntervalSinceReferenceDate
                ZStack {
                    CoveMascotView(state: state, scale: .pet, grounded: false)
                        .offset(y: isDragging ? 0 : verticalOffset(time, state: state))
                        .scaleEffect(breathScale(time))


                    if hasAttention && !isDragging {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .offset(x: 16, y: -16)
                            .opacity(0.6 + sin(time * .pi * 4) * 0.4)
                    }
                }
            }
            .allowsHitTesting(false)
        }
        .frame(width: 48, height: 48)
    }

    private func verticalOffset(_ time: TimeInterval, state: PixelMascotState) -> CGFloat {
        switch state {
        case .working:   CGFloat(sin(time * .pi * 5) * 1.5)
        case .idle:      CGFloat(sin(time * .pi * 1.2) * 0.8)
        case .sleeping:  CGFloat(sin(time * .pi * 0.8) * 0.6)
        case .attention: CGFloat(sin(time * .pi * 7) * 2.0)
        case .dragged:   0
        }
    }

    private func breathScale(_ time: TimeInterval) -> CGFloat {
        let base = 1.0 + sin(time * .pi * 0.6) * 0.02
        return hasAttention ? base + sin(time * .pi * 3) * 0.04 : base
    }
}


