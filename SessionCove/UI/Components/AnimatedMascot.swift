import SwiftUI

struct AnimatedMascot: View {
    let active: Bool
    let archived: Bool
    let size: CGFloat
    var stateOverride: PixelMascotState?

    private var state: PixelMascotState {
        if let stateOverride { return stateOverride }
        if active { return .working }
        if archived { return .sleeping }
        return .idle
    }

    var body: some View {
        PixelOctopusSprite(state: state)
            .frame(width: size, height: size)
            .opacity(archived ? 0.88 : 1.0)
            .saturation(active ? 1.08 : archived ? 0.72 : 0.95)
    }

    private func verticalOffset(_ time: TimeInterval) -> CGFloat {
        switch state {
        case .working:
            return CGFloat(sin(time * .pi * 5) * 1.5)
        case .idle:
            return CGFloat(sin(time * .pi * 1.2) * 0.8)
        case .sleeping:
            return CGFloat(sin(time * .pi * 0.8) * 0.6)
        case .attention:
            return CGFloat(sin(time * .pi * 7) * 2.0)
        }
    }
}
