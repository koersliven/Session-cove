import SwiftUI

/// macOS notch-shaped capsule with asymmetric corner radii.
/// closed: top corners 6pt, bottom corners 14pt — sits flush against the menu bar.
/// opened: top corners 19pt, bottom corners 24pt — used when the panel grows.
/// PR 3 only renders closed; PR 4 introduces opened/peeking variants.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        // Manually trace 4 arcs + 4 lines so top/bottom corner radii can differ.
        // UnevenRoundedRectangle (macOS 13+) would also work; manual path keeps a
        // single code path and matches ping-island's NotchShape implementation.
        var path = Path()
        let topR = min(topRadius, min(rect.width, rect.height) / 2)
        let botR = min(bottomRadius, min(rect.width, rect.height) / 2)

        path.move(to: CGPoint(x: rect.minX + topR, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - topR, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - topR, y: rect.minY + topR),
            radius: topR,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - botR))
        path.addArc(
            center: CGPoint(x: rect.maxX - botR, y: rect.maxY - botR),
            radius: botR,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX + botR, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + botR, y: rect.maxY - botR),
            radius: botR,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topR))
        path.addArc(
            center: CGPoint(x: rect.minX + topR, y: rect.minY + topR),
            radius: topR,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

extension NotchShape {
    static let closed = NotchShape(topRadius: 6, bottomRadius: 14)
    static let opened = NotchShape(topRadius: 19, bottomRadius: 24)
}
