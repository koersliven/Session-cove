import SwiftUI

struct CrewCountBuoy: View {
    let count: Int
    var isActive: Bool = false

    var body: some View {
        ZStack {
            // Buoy body
            RoundedRectangle(cornerRadius: 4)
                .fill(buoyColor)
                .frame(width: 26, height: 22)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(PixelPalette.ink.opacity(0.4), lineWidth: 2)
                )

            // Stripe
            Rectangle()
                .fill(.white.opacity(0.3))
                .frame(width: 26, height: 3)

            // Count text
            Text("\(count)")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(.white)
        }
    }

    private var buoyColor: Color {
        isActive ? Color(red: 0.15, green: 0.55, blue: 0.35) : Color(red: 0.18, green: 0.35, blue: 0.50)
    }
}
