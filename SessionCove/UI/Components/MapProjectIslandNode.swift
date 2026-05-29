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
    @State private var heartTick: Int = 0

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
                        ZStack {
                            ActiveSeaweed()
                            ActiveIslandBubbles()
                                .offset(x: 0, y: -20)
                        }
                        .offset(x: -24, y: -14)

                        ActiveIslandBubbles()
                            .offset(x: 20, y: -18)
                    }

                    if hasPendingPermission {
                        PermissionBeacon()
                            .offset(x: -18, y: -14)
                    }

                    if isSelected {
                        SelectionSparkles(phase: sparklePhase)
                        FloatingBubbles(tick: heartTick)
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
                startHeartEmission()
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

    private func startHeartEmission() {
        heartTick += 1
    }

    // MARK: - Spotlight beam

    private var spotlight: some View {
        Canvas { context, size in
            let cx = size.width / 2
            let topWidth: CGFloat = 20 * spotlightWidth
            let bottomWidth: CGFloat = 80 * spotlightWidth
            let beamHeight: CGFloat = size.height

            var beamPath = Path()
            beamPath.move(to: CGPoint(x: cx - topWidth / 2, y: -14))
            beamPath.addLine(to: CGPoint(x: cx + topWidth / 2, y: -14))
            beamPath.addLine(to: CGPoint(x: cx + bottomWidth / 2, y: beamHeight))
            beamPath.addLine(to: CGPoint(x: cx - bottomWidth / 2, y: beamHeight))
            beamPath.closeSubpath()

            let gradient = Gradient(stops: [
                .init(color: Color(red: 0.5, green: 0.95, blue: 1.0).opacity(0.5), location: 0),
                .init(color: Color(red: 0.4, green: 0.85, blue: 1.0).opacity(0.25), location: 0.35),
                .init(color: Color(red: 0.3, green: 0.7, blue: 0.95).opacity(0.06), location: 1.0),
            ])

            context.fill(
                beamPath,
                with: .linearGradient(
                    gradient,
                    startPoint: CGPoint(x: cx, y: -14),
                    endPoint: CGPoint(x: cx, y: beamHeight)
                )
            )
        }
        .frame(width: 140, height: 90)
        .blur(radius: 4)
        .opacity(0.8 + Double(pulsePhase) * 0.2)
        .allowsHitTesting(false)
    }

    // MARK: - Ground glow

    private var selectionGlow: some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [
                        Color(red: 0.4, green: 0.95, blue: 1.0).opacity(0.9),
                        Color(red: 0.3, green: 0.8, blue: 1.0).opacity(0.4),
                        Color(red: 0.2, green: 0.65, blue: 0.95).opacity(0.12),
                        .clear
                    ],
                    center: .center,
                    startRadius: 2,
                    endRadius: 50
                )
            )
            .frame(width: 105 * spotlightWidth, height: 44 * spotlightWidth)
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

// MARK: - Floating Bubbles

struct FloatingBubbles: View {
    let tick: Int

    @State private var bubbles: [BubbleParticle] = []
    @State private var timer: Timer?

    var body: some View {
        ZStack {
            ForEach(bubbles) { bubble in
                Circle()
                    .stroke(Color(red: 0.6, green: 0.95, blue: 1.0).opacity(bubble.opacity * 0.8), lineWidth: 1)
                    .background(
                        Circle().fill(Color(red: 0.5, green: 0.9, blue: 1.0).opacity(bubble.opacity * 0.15))
                    )
                    .frame(width: bubble.size, height: bubble.size)
                    .offset(x: bubble.x, y: bubble.y)
                    .opacity(bubble.opacity)
            }
        }
        .onAppear { startEmitting() }
        .onChange(of: tick) { _, _ in startEmitting() }
        .onDisappear { timer?.invalidate() }
    }

    private func startEmitting() {
        timer?.invalidate()
        bubbles = []
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            let newBubble = BubbleParticle(
                x: CGFloat.random(in: -8...8),
                y: -2,
                size: CGFloat.random(in: 4...9),
                opacity: 0.9
            )
            bubbles.append(newBubble)

            withAnimation(.easeOut(duration: 2.2)) {
                if let idx = bubbles.firstIndex(where: { $0.id == newBubble.id }) {
                    bubbles[idx].y = CGFloat.random(in: -38 ... -22)
                    bubbles[idx].x += CGFloat.random(in: -12...12)
                    bubbles[idx].opacity = 0
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                bubbles.removeAll { $0.opacity <= 0.01 }
            }
        }
    }
}

struct BubbleParticle: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var size: CGFloat
    var opacity: Double
}

// MARK: - Sparkles

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

// MARK: - Active Island Glow

struct ActiveSeaweed: View {
    @State private var sway: CGFloat = 0

    private let lightGreen = Color(red: 0.30, green: 0.75, blue: 0.40)
    private let midGreen = Color(red: 0.18, green: 0.60, blue: 0.30)
    private let darkGreen = Color(red: 0.10, green: 0.42, blue: 0.22)

    var body: some View {
        Canvas { context, size in
            let base = CGPoint(x: size.width * 0.45, y: size.height)
            let px: CGFloat = 2.2
            let sw = sway * 2.2

            struct Pixel {
                let x: CGFloat; let y: CGFloat; let color: Color
            }

            let stalk: [Pixel] = [
                Pixel(x: 0, y: 0, color: darkGreen),
                Pixel(x: 0, y: -1, color: darkGreen),
                Pixel(x: 0, y: -2, color: midGreen),
                Pixel(x: 0, y: -3, color: midGreen),
                Pixel(x: -0.2, y: -4, color: midGreen),
                Pixel(x: -0.4, y: -5, color: lightGreen),
                Pixel(x: -0.3, y: -6, color: lightGreen),
                Pixel(x: 0, y: -7, color: lightGreen),
                Pixel(x: 0.2, y: -8, color: lightGreen),
                Pixel(x: 0.1, y: -9, color: lightGreen),
            ]

            let leaves: [Pixel] = [
                Pixel(x: 1, y: -2.5, color: midGreen),
                Pixel(x: 2, y: -3, color: midGreen),
                Pixel(x: 2.5, y: -3.5, color: lightGreen),
                Pixel(x: -1, y: -4, color: midGreen),
                Pixel(x: -2, y: -4.5, color: lightGreen),
                Pixel(x: -2.5, y: -5, color: lightGreen),
                Pixel(x: 1, y: -5.5, color: midGreen),
                Pixel(x: 2, y: -6, color: lightGreen),
                Pixel(x: -1, y: -7, color: lightGreen),
                Pixel(x: -1.8, y: -7.5, color: lightGreen),
                Pixel(x: 0.8, y: -8.5, color: lightGreen),
                Pixel(x: 1.5, y: -9, color: lightGreen),
            ]

            for pixel in stalk + leaves {
                let h = abs(pixel.y) / 9.0
                let xPos = base.x + (pixel.x + sw * h * h) * px
                let yPos = base.y + pixel.y * px
                let rect = CGRect(x: xPos, y: yPos, width: px, height: px)
                context.fill(Path(rect), with: .color(pixel.color))
            }
        }
        .frame(width: 24, height: 26)
        .shadow(color: PixelPalette.grass.opacity(0.4), radius: 3)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                    sway = 1
                }
            }
        }
    }
}

struct SeaweedBubbles: View {
    @State private var bubbles: [GreenBubble] = []
    @State private var timer: Timer?

    var body: some View {
        ZStack {
            ForEach(bubbles) { bubble in
                Circle()
                    .fill(PixelPalette.grass.opacity(bubble.opacity * 0.6))
                    .overlay(
                        Circle()
                            .stroke(PixelPalette.grass.opacity(bubble.opacity * 0.8), lineWidth: 0.8)
                    )
                    .frame(width: bubble.size, height: bubble.size)
                    .offset(x: bubble.x, y: bubble.y)
            }
        }
        .frame(width: 20, height: 30)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 0.5...1.2)) {
                startEmitting()
            }
        }
        .onDisappear { timer?.invalidate() }
    }

    private func startEmitting() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { _ in
            let newBubble = GreenBubble(
                x: CGFloat.random(in: -5...5),
                y: 0,
                size: CGFloat.random(in: 2.5...4.5),
                opacity: 0.9
            )
            bubbles.append(newBubble)

            withAnimation(.easeOut(duration: 1.8)) {
                if let idx = bubbles.firstIndex(where: { $0.id == newBubble.id }) {
                    bubbles[idx].y = CGFloat.random(in: -20 ... -12)
                    bubbles[idx].x += CGFloat.random(in: -6...6)
                    bubbles[idx].opacity = 0
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                bubbles.removeAll { $0.opacity <= 0.01 }
            }
        }
    }
}

struct GreenBubble: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var size: CGFloat
    var opacity: Double
}

// MARK: - Active Island Bubbles (prominent, visible at map level)

struct ActiveIslandBubbles: View {
    @State private var bubbles: [GreenBubble] = []
    @State private var timer: Timer?

    var body: some View {
        ZStack {
            ForEach(bubbles) { bubble in
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.3, green: 0.9, blue: 0.5).opacity(bubble.opacity * 0.5),
                                Color(red: 0.2, green: 0.8, blue: 0.4).opacity(bubble.opacity * 0.2)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: bubble.size / 2
                        )
                    )
                    .overlay(
                        Circle()
                            .stroke(
                                Color(red: 0.4, green: 1.0, blue: 0.6).opacity(bubble.opacity * 0.7),
                                lineWidth: 1.2
                            )
                    )
                    .frame(width: bubble.size, height: bubble.size)
                    .offset(x: bubble.x, y: bubble.y)
            }
        }
        .frame(width: 36, height: 50)
        .onAppear { deferredStart() }
        .onDisappear { timer?.invalidate() }
    }

    private func deferredStart() {
        let delay = Double.random(in: 0.4...1.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            startEmitting()
        }
    }

    private func startEmitting() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { _ in
            let newBubble = GreenBubble(
                x: CGFloat.random(in: -10...10),
                y: 0,
                size: CGFloat.random(in: 4...9),
                opacity: 1.0
            )
            bubbles.append(newBubble)

            withAnimation(.easeOut(duration: 2.6)) {
                if let idx = bubbles.firstIndex(where: { $0.id == newBubble.id }) {
                    bubbles[idx].y = CGFloat.random(in: -42 ... -24)
                    bubbles[idx].x += CGFloat.random(in: -10...10)
                    bubbles[idx].opacity = 0
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                bubbles.removeAll { $0.opacity <= 0.01 }
            }
        }
    }
}
