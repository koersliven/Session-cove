import SwiftUI

struct CoveShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let w = rect.width
        let h = rect.height
        let midY = h * 0.45

        path.move(to: CGPoint(x: w * 0.08, y: h * 0.75))

        path.addQuadCurve(
            to: CGPoint(x: w * 0.25, y: midY),
            control: CGPoint(x: w * 0.05, y: midY + h * 0.1)
        )
        path.addQuadCurve(
            to: CGPoint(x: w * 0.5, y: midY - h * 0.12),
            control: CGPoint(x: w * 0.35, y: midY - h * 0.15)
        )
        path.addQuadCurve(
            to: CGPoint(x: w * 0.75, y: midY),
            control: CGPoint(x: w * 0.65, y: midY - h * 0.15)
        )
        path.addQuadCurve(
            to: CGPoint(x: w * 0.92, y: h * 0.75),
            control: CGPoint(x: w * 0.95, y: midY + h * 0.1)
        )

        path.addQuadCurve(
            to: CGPoint(x: w * 0.08, y: h * 0.75),
            control: CGPoint(x: w * 0.5, y: h * 0.88)
        )

        path.closeSubpath()
        return path
    }
}
