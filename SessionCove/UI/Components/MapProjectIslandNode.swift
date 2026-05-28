import SwiftUI

struct MapProjectIslandNode: View {
    let island: ProjectIsland
    var isSelected: Bool = false
    var hasPendingPermission: Bool = false
    let onTap: () -> Void

    @State private var isHovered = false
    @State private var sparklePhase: CGFloat = 0
    @State private var pulsePhase: CGFloat = 0
    @State private var floatOffset: CGFloat = 0
    @State private var spotlightWidth: CGFloat = 0

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                ZStack(alignment: .center) {
                    if isSelected {
                        spotlight
                        selectionGlow
                    }

                    PixelIslandSprite(mood: islandMood)
                        .saturation(islandMood.saturation)
                        .brightness(isSelected ? islandMood.brightness + 0.08 : islandMood.brightness)

                    CoveMascotView(state: mascotState, scale: .row)
                        .offset(y: isSelected ? 4 + floatOffset : 4)

                    if island.activeCount > 0 {
                        Circle()
                            .fill(PixelPalette.grass)
                            .frame(width: 4, height: 4)
                            .shadow(color: PixelPalette.grass.opacity(0.7), radius: 4)
                            .offset(x: 16, y: 4)
                    }

                    if hasPendingPermission {
                        PermissionBeacon()
                            .offset(x: -18, y: -14)
                    }

                    if isSelected {
                        SelectionSparkles(phase: sparklePhase)
                    }
                }

                Text(island.displayName)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(isSelected ? 1.0 : 0.72))
                    .lineLimit(1)
                    .padding(.top, 2)
                    .shadow(color: isSelected ? Color(red: 0.4, green: 0.9, blue: 1.0).opacity(0.8) : .clear, radius: 4)
            }
            .scaleEffect(isHovered ? 1.12 : (isSelected ? 1.22 : 1.0))
            .animation(.interpolatingSpring(stiffness: 200, damping: 8), value: isSelected)
            .animation(.snappy(duration: 0.14), value: isHovered)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .onChange(of: isSelected) { _, selected in
            if selected {
                spotlightWidth = 0
                withAnimation(.easeOut(duration: 0.4)) {
                    spotlightWidth = 1
                }
                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                    sparklePhase = 1
                }
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    pulsePhase = 1
                }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    floatOffset = -3.5
                }
            } else {
                withAnimation(.easeIn(duration: 0.2)) {
                    spotlightWidth = 0
                }
                sparklePhase = 0
                pulsePhase = 0
                floatOffset = 0
            }
        }
    }

    // MARK: - Spotlight beam from above

    private var spotlight: some View {
        Canvas { context, size in
            let cx = size.width / 2
            let topWidth: CGFloat = 16 * spotlightWidth
            let bottomWidth: CGFloat = 70 * spotlightWidth
            let beamHeight: CGFloat = size.height * 0.9

            var beamPath = Path()
            beamPath.move(to: CGPoint(x: cx - topWidth / 2, y: -10))
            beamPath.addLine(to: CGPoint(x: cx + topWidth / 2, y: -10))
            beamPath.addLine(to: CGPoint(x: cx + bottomWidth / 2, y: beamHeight))
            beamPath.addLine(to: CGPoint(x: cx - bottomWidth / 2, y: beamHeight))
            beamPath.closeSubpath()

            let gradient = Gradient(stops: [
                .init(color: Color(red: 0.5, green: 0.95, blue: 1.0).opacity(0.4), location: 0),
                .init(color: Color(red: 0.4, green: 0.85, blue: 1.0).opacity(0.2), location: 0.4),
                .init(color: Color(red: 0.3, green: 0.7, blue: 0.95).opacity(0.05), location: 1.0),
            ])

            context.fill(
                beamPath,
                with: .linearGradient(
                    gradient,
                    startPoint: CGPoint(x: cx, y: -10),
                    endPoint: CGPoint(x: cx, y: beamHeight)
                )
            )
        }
        .frame(width: 120, height: 80)
        .blur(radius: 3)
        .opacity(0.7 + Double(pulsePhase) * 0.3)
        .allowsHitTesting(false)
    }

    // MARK: - Ground glow

    private var selectionGlow: some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [
                        Color(red: 0.4, green: 0.95, blue: 1.0).opacity(0.8),
                        Color(red: 0.3, green: 0.8, blue: 1.0).opacity(0.4),
                        Color(red: 0.2, green: 0.65, blue: 0.95).opacity(0.12),
                        .clear
                    ],
                    center: .center,
                    startRadius: 2,
                    endRadius: 50
                )
            )
            .frame(width: 100 * spotlightWidth, height: 40 * spotlightWidth)
            .offset(y: 12)
            .blur(radius: 5)
            .opacity(0.6 + Double(pulsePhase) * 0.4)
    }

    private var mascotState: PixelMascotState {
        if hasPendingPermission { return .attention }
        if island.activeCount > 0 { return .working }
        if island.recentCount > 0 { return .idle }
        return .sleeping
    }

    private var islandMood: IslandMood {
        if island.activeCount > 0 { return .active }
        if island.recentCount > 0 { return .recent }
        return .archived
    }
}

struct SelectionSparkles: View {
    let phase: CGFloat

    private let sparkles: [(offset: CGSize, size: CGFloat, delay: CGFloat)] = [
        (CGSize(width: -34, height: -16), 8, 0.0),
        (CGSize(width: 30, height: -14), 10, 0.2),
        (CGSize(width: -20, height: 12), 7, 0.4),
        (CGSize(width: 34, height: 8), 8, 0.1),
        (CGSize(width: 0, height: -26), 11, 0.3),
        (CGSize(width: -38, height: 4), 7, 0.55),
        (CGSize(width: 22, height: -24), 6, 0.7),
        (CGSize(width: -10, height: 16), 7, 0.85),
        (CGSize(width: 38, height: -4), 9, 0.45),
        (CGSize(width: -26, height: -22), 6, 0.65),
    ]

    var body: some View {
        ForEach(0..<sparkles.count, id: \.self) { i in
            let sparkle = sparkles[i]
            let t = (phase + sparkle.delay).truncatingRemainder(dividingBy: 1.0)
            let opacity = sin(t * .pi)
            let scale = 0.6 + sin(t * .pi) * 0.4

            SparkleShape()
                .fill(Color.white)
                .frame(width: sparkle.size, height: sparkle.size)
                .scaleEffect(scale)
                .opacity(Double(opacity))
                .shadow(color: Color(red: 0.5, green: 0.95, blue: 1.0).opacity(Double(opacity) * 0.8), radius: 4)
                .shadow(color: .white.opacity(Double(opacity) * 0.5), radius: 2)
                .offset(sparkle.offset)
        }
    }
}

struct SparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cx = rect.midX
        let cy = rect.midY
        let r = min(rect.width, rect.height) / 2

        path.move(to: CGPoint(x: cx, y: cy - r))
        path.addLine(to: CGPoint(x: cx + r * 0.15, y: cy - r * 0.15))
        path.addLine(to: CGPoint(x: cx + r, y: cy))
        path.addLine(to: CGPoint(x: cx + r * 0.15, y: cy + r * 0.15))
        path.addLine(to: CGPoint(x: cx, y: cy + r))
        path.addLine(to: CGPoint(x: cx - r * 0.15, y: cy + r * 0.15))
        path.addLine(to: CGPoint(x: cx - r, y: cy))
        path.addLine(to: CGPoint(x: cx - r * 0.15, y: cy - r * 0.15))
        path.closeSubpath()
        return path
    }
}
