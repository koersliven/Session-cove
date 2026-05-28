import SwiftUI

struct IslandShelfShape: View {
    var mood: IslandMood = .recent

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let unit: CGFloat = 4

            Canvas { context, size in
                // Dark underside (pixel shadow)
                let undersidePath = Path { p in
                    p.move(to: CGPoint(x: unit * 3, y: h - unit * 2))
                    p.addLine(to: CGPoint(x: w - unit * 3, y: h - unit * 2))
                    p.addLine(to: CGPoint(x: w - unit, y: h))
                    p.addLine(to: CGPoint(x: unit, y: h))
                    p.closeSubpath()
                }
                context.fill(undersidePath, with: .color(PixelPalette.ink.opacity(0.5)))

                // Sand body
                let sandPath = Path { p in
                    p.move(to: CGPoint(x: unit * 4, y: unit * 4))
                    p.addLine(to: CGPoint(x: w - unit * 4, y: unit * 4))
                    p.addLine(to: CGPoint(x: w - unit * 2, y: h * 0.5))
                    p.addLine(to: CGPoint(x: w - unit * 3, y: h - unit * 2))
                    p.addLine(to: CGPoint(x: unit * 3, y: h - unit * 2))
                    p.addLine(to: CGPoint(x: unit * 2, y: h * 0.5))
                    p.closeSubpath()
                }
                context.fill(sandPath, with: .color(mood.sand.opacity(0.85)))

                // Grass top strip
                let grassHeight = h * 0.28
                let grassPath = Path { p in
                    p.move(to: CGPoint(x: unit * 5, y: unit * 2))
                    p.addLine(to: CGPoint(x: w - unit * 5, y: unit * 2))
                    p.addLine(to: CGPoint(x: w - unit * 4, y: unit * 2 + grassHeight))
                    p.addLine(to: CGPoint(x: unit * 4, y: unit * 2 + grassHeight))
                    p.closeSubpath()
                }
                context.fill(grassPath, with: .color(mood.grass.opacity(0.9)))

                // Pixel outline (top edge)
                for x in stride(from: unit * 4, to: w - unit * 4, by: unit) {
                    context.fill(
                        Path(CGRect(x: x, y: unit, width: unit, height: unit)),
                        with: .color(PixelPalette.ink.opacity(0.6))
                    )
                }

                // Water foam at bottom
                for x in stride(from: unit * 2, to: w - unit * 2, by: unit * 3) {
                    let wave = Int(x / unit) % 5
                    if wave < 2 {
                        context.fill(
                            Path(CGRect(x: x, y: h - unit, width: unit * 2, height: unit)),
                            with: .color(mood.waterEdge)
                        )
                    }
                }
            }
        }
    }
}
