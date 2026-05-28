import SwiftUI

struct WaterLaneBackground: View {
    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let unit: CGFloat = 6

                // Subtle horizontal wave lines
                for row in stride(from: unit * 2, to: size.height, by: unit * 4) {
                    for col in stride(from: 0, to: size.width, by: unit * 5) {
                        let offset = Int(row / unit) % 2 == 0 ? unit : 0
                        let waveX = col + offset
                        if Int(waveX + row) % 7 < 2 {
                            context.fill(
                                Path(CGRect(x: waveX, y: row, width: unit * 2, height: 2)),
                                with: .color(PixelPalette.foam.opacity(0.08))
                            )
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}
