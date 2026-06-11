import SwiftUI
import Combine

struct PetMascotView: View {
    @Bindable var viewModel: CoveViewModel
    @State private var isDragging = false
    /// Loaded once per path change (not per frame) so disk I/O stays off the
    /// 30fps render path. Seeded by the `onReceive` below, which fires with
    /// the current `customPetImagePath` value on subscription.
    @State private var customPetImage: NSImage?
    @State private var petSize: Double = CoveSettings.currentPetSize

    private var mascotState: PixelMascotState {
        // Highest priority: drag + permission attention. Pet micro
        // actions never override these.
        if isDragging { return .dragged }
        if viewModel.pendingHookRequest != nil { return .attention }
        // Pet ambient micro-action (blink/sip/bubble) — only valid on
        // top of the working / idle baseline; viewModel scheduler clears
        // it after ~1s.
        if let micro = viewModel.currentPetMicroState { return micro }
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
                    CoveMascotView(
                        state: state,
                        scale: .pet,
                        grounded: false,
                        providerPrefix: viewModel.activePetProviderId,
                        customImage: customPetImage,
                        overrideSize: CGSize(width: petSize, height: petSize)
                    )
                        .offset(y: isDragging ? 0 : verticalOffset(time, state: state))
                        .scaleEffect(breathScale(time))


                    if hasAttention && !isDragging {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .offset(x: 16, y: -16)
                            .opacity(0.6 + sin(time * .pi * 4) * 0.4)
                    }

                    if viewModel.hasUnreadReport && !isDragging {
                        Circle()
                            .fill(.cyan)
                            .frame(width: 7, height: 7)
                            .offset(x: -16, y: -16)
                            .opacity(0.5 + sin(time * .pi * 3) * 0.3)
                    }

                    if !UpdateChecker.shared.dismissed,
                       case .available = UpdateChecker.shared.state,
                       !isDragging {
                        Circle()
                            .fill(.orange)
                            .frame(width: 7, height: 7)
                            .offset(x: 0, y: -22)
                            .opacity(0.5 + sin(time * .pi * 3.5) * 0.3)
                    }
                }
            }
            .allowsHitTesting(false)
        }
        .frame(width: petSize, height: petSize)
        .onReceive(CoveSettings.shared.$customPetImagePath) { newPath in
            customPetImage = MascotImage.loadCustom(path: newPath)
        }
        .onReceive(CoveSettings.shared.$petDisplaySize) { newSize in
            petSize = newSize
        }
    }

    private func verticalOffset(_ time: TimeInterval, state: PixelMascotState) -> CGFloat {
        switch state {
        case .working:       CGFloat(sin(time * .pi * 5) * 1.5)
        case .idle:          CGFloat(sin(time * .pi * 1.2) * 0.8)
        case .sleeping:      CGFloat(sin(time * .pi * 0.8) * 0.6)
        case .attention:     CGFloat(sin(time * .pi * 7) * 2.0)
        case .dragged:       0
        // Pet micro-actions: gentle breathing-style float so the sprite
        // doesn't read as static during the action.
        case .petBlink:      CGFloat(sin(time * .pi * 1.4) * 0.6)
        case .petSip:        CGFloat(sin(time * .pi * 2.2) * 0.8)
        case .petBubble:     CGFloat(sin(time * .pi * 2.6) * 1.2)
        case .petCelebrate:  CGFloat(abs(sin(time * .pi * 6)) * 2.0)
        }
    }

    private func breathScale(_ time: TimeInterval) -> CGFloat {
        let base = 1.0 + sin(time * .pi * 0.6) * 0.02
        return hasAttention ? base + sin(time * .pi * 3) * 0.04 : base
    }
}


