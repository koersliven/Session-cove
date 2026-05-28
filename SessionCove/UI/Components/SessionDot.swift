import SwiftUI

struct SessionDot: View {
    let status: SessionStatus

    var body: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 8, height: 8)
            .overlay {
                if status == .active {
                    Circle()
                        .stroke(dotColor.opacity(0.5), lineWidth: 2)
                        .frame(width: 12, height: 12)
                        .scaleEffect(pulseScale)
                        .opacity(pulseOpacity)
                        .animation(
                            .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                            value: pulseScale
                        )
                }
            }
            .onAppear {
                if status == .active {
                    pulseScale = 1.3
                    pulseOpacity = 0
                }
            }
    }

    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 1.0

    private var dotColor: Color {
        switch status {
        case .active: .green
        case .recentlyIdle: .yellow
        case .archived: .gray.opacity(0.5)
        }
    }
}
