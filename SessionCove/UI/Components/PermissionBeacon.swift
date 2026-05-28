import SwiftUI

struct PermissionBeacon: View {
    @State private var glowPhase: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Beacon light
            Circle()
                .fill(PixelPalette.alert)
                .frame(width: 8, height: 8)
                .shadow(color: PixelPalette.alert.opacity(glowPhase ? 0.8 : 0.3), radius: glowPhase ? 6 : 2)

            // Pole
            Rectangle()
                .fill(PixelPalette.sand)
                .frame(width: 3, height: 12)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                glowPhase = true
            }
        }
    }
}
