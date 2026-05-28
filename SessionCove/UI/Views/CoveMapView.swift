import SwiftUI

struct CoveMapView: View {
    @Bindable var viewModel: CoveViewModel

    var body: some View {
        ZStack {
            PixelOceanBackground()
            islandMap
            topBar
            bottomDock
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var topIslands: [ProjectIsland] {
        viewModel.islands
            .sorted { lhs, rhs in
                let lhsTime = lhs.sessions.first?.lastModified ?? .distantPast
                let rhsTime = rhs.sessions.first?.lastModified ?? .distantPast
                return lhsTime > rhsTime
            }
            .prefix(6)
            .map { $0 }
    }

    private var islandMap: some View {
        GeometryReader { geo in
            let islands = topIslands
            let slots = IslandSlot.slots(in: geo.size)

            ZStack {
                PixelSeaPaths(slots: Array(slots.prefix(islands.count)))

                if islands.isEmpty {
                    emptyState
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }

                ForEach(Array(islands.enumerated()), id: \.element.id) { index, island in
                    if index < slots.count {
                        let slot = slots[index]
                        ProjectIslandView(
                            island: island,
                            scale: slot.scale,
                            pendingRequest: viewModel.pendingHookRequest
                        )
                        .position(slot.point)
                        .onTapGesture {
                            viewModel.selectIsland(island)
                        }
                        .transition(.scale(scale: 0.88).combined(with: .opacity))
                    }
                }

                if viewModel.islands.count > islands.count, let last = slots.prefix(islands.count).last {
                    pixelTag("+\(viewModel.islands.count - islands.count)")
                        .position(x: last.point.x, y: last.point.y + 118 * last.scale)
                }
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    private var topBar: some View {
        VStack {
            HStack(alignment: .top) {
                PixelHUDPanel {
                    HStack(spacing: 8) {
                        PixelOctopusSprite(state: .idle)
                            .frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("SESSION COVE")
                                .font(.system(size: 12, weight: .black, design: .monospaced))
                                .foregroundStyle(.white)
                            Text("\(viewModel.islands.count) islands / \(viewModel.totalSessions) sessions")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(PixelPalette.foam.opacity(0.84))
                        }
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    pixelButton("TEST") {
                        viewModel.showMockHookRequest()
                    }
                    pixelButton("X") {
                        viewModel.toggle()
                    }
                }
            }
            .padding(12)
            Spacer()
        }
    }

    private var bottomDock: some View {
        VStack {
            Spacer()
            HStack {
                PixelHUDPanel {
                    HStack(spacing: 12) {
                        legendSwatch(PixelPalette.grass, "active")
                        legendSwatch(PixelPalette.sand, "idle")
                        legendSwatch(Color(red: 0.50, green: 0.49, blue: 0.42), "sleep")
                        if viewModel.pendingHookRequest != nil {
                            legendSwatch(PixelPalette.alert, "approval")
                        }
                    }
                }
                Spacer()
            }
            .padding(12)
        }
    }

    private var emptyState: some View {
        PixelHUDPanel {
            VStack(spacing: 8) {
                PixelIslandSprite(mood: .archived)
                    .frame(width: 180, height: 100)
                Text("NO ISLANDS")
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundStyle(.white)
                Text("start Claude Code in a project")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(PixelPalette.foam.opacity(0.84))
            }
        }
        .frame(width: 340)
    }

    private func pixelButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background {
                    PixelBox(fill: Color(red: 0.12, green: 0.24, blue: 0.34), edge: PixelPalette.foam.opacity(0.58))
                }
        }
        .buttonStyle(.plain)
    }

    private func legendSwatch(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Rectangle().fill(color).frame(width: 8, height: 8)
            Text(label.uppercased())
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundStyle(.white.opacity(0.82))
        }
    }

    private func pixelTag(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .black, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background { PixelBox(fill: PixelPalette.hud.opacity(0.90), edge: PixelPalette.hudEdge) }
    }
}

private struct IslandSlot: Sendable {
    let point: CGPoint
    let scale: CGFloat

    static func slots(in size: CGSize) -> [IslandSlot] {
        let mapRect = CGRect(
            x: 28,
            y: 76,
            width: max(1, size.width - 56),
            height: max(1, size.height - 150)
        )
        let scalePlan: [CGFloat] = [1.12, 0.82, 0.78, 0.74, 0.70, 0.66]
        let normalizedSeeds = [
            CGPoint(x: 0.50, y: 0.50),
            CGPoint(x: 0.21, y: 0.24),
            CGPoint(x: 0.79, y: 0.24),
            CGPoint(x: 0.78, y: 0.76),
            CGPoint(x: 0.22, y: 0.76),
            CGPoint(x: 0.50, y: 0.16),
            CGPoint(x: 0.50, y: 0.84),
            CGPoint(x: 0.12, y: 0.50),
            CGPoint(x: 0.88, y: 0.50)
        ]

        var placed: [IslandSlot] = []
        for index in 0..<scalePlan.count {
            let scale = scalePlan[index]
            let size = islandBounds(for: scale)
            let candidates = candidatePoints(
                from: normalizedSeeds[index],
                in: mapRect,
                avoiding: placed,
                bounds: size
            )
            let point = candidates.first { candidate in
                let rect = CGRect(
                    x: candidate.x - size.width / 2,
                    y: candidate.y - size.height / 2,
                    width: size.width,
                    height: size.height
                )
                return mapRect.contains(rect) && !placed.contains { existing in
                    rect.insetBy(dx: -18, dy: -14).intersects(existing.rect)
                }
            } ?? clampedPoint(normalizedSeeds[index], in: mapRect, bounds: size)
            placed.append(IslandSlot(point: point, scale: scale))
        }
        return placed
    }

    private var rect: CGRect {
        let size = Self.islandBounds(for: scale)
        return CGRect(
            x: point.x - size.width / 2,
            y: point.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private static func islandBounds(for scale: CGFloat) -> CGSize {
        CGSize(width: 420 * scale, height: 238 * scale)
    }

    private static func candidatePoints(
        from seed: CGPoint,
        in rect: CGRect,
        avoiding placed: [IslandSlot],
        bounds: CGSize
    ) -> [CGPoint] {
        let base = clampedPoint(seed, in: rect, bounds: bounds)
        var points = [base]
        let stepX = max(32, bounds.width * 0.18)
        let stepY = max(26, bounds.height * 0.18)
        let searchRings: [CGFloat] = [1, 2, 3, 4, 5, 6]
        for ring in searchRings {
            for direction in searchDirections {
                points.append(CGPoint(
                    x: base.x + direction.x * stepX * ring,
                    y: base.y + direction.y * stepY * ring
                ))
            }
        }
        return points
            .map { point in clamp(point, in: rect, bounds: bounds) }
            .sorted { lhs, rhs in
                let lhsDistance = distanceSquared(lhs, base)
                let rhsDistance = distanceSquared(rhs, base)
                if lhsDistance == rhsDistance {
                    return distanceSquared(lhs, CGPoint(x: rect.midX, y: rect.midY)) < distanceSquared(rhs, CGPoint(x: rect.midX, y: rect.midY))
                }
                return lhsDistance < rhsDistance
            }
    }

    private static var searchDirections: [CGPoint] {
        [
            CGPoint(x: 1, y: 0), CGPoint(x: -1, y: 0),
            CGPoint(x: 0, y: 1), CGPoint(x: 0, y: -1),
            CGPoint(x: 1, y: 1), CGPoint(x: -1, y: 1),
            CGPoint(x: 1, y: -1), CGPoint(x: -1, y: -1)
        ]
    }

    private static func clampedPoint(_ normalized: CGPoint, in rect: CGRect, bounds: CGSize) -> CGPoint {
        clamp(
            CGPoint(
                x: rect.minX + rect.width * normalized.x,
                y: rect.minY + rect.height * normalized.y
            ),
            in: rect,
            bounds: bounds
        )
    }

    private static func clamp(_ point: CGPoint, in rect: CGRect, bounds: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(point.x, rect.minX + bounds.width / 2), rect.maxX - bounds.width / 2),
            y: min(max(point.y, rect.minY + bounds.height / 2), rect.maxY - bounds.height / 2)
        )
    }

    private static func distanceSquared(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return dx * dx + dy * dy
    }
}

private struct PixelSeaPaths: View {
    let slots: [IslandSlot]

    var body: some View {
        Canvas { context, _ in
            guard slots.count > 1 else { return }
            let origin = slots[0].point
            for slot in slots.dropFirst().prefix(5) {
                drawPixelPath(from: origin, to: slot.point, context: &context)
            }
        }
        .allowsHitTesting(false)
    }

    private func drawPixelPath(from start: CGPoint, to end: CGPoint, context: inout GraphicsContext) {
        let steps = 14
        for step in 0...steps {
            if step % 2 == 0 {
                let t = CGFloat(step) / CGFloat(steps)
                let x = start.x + (end.x - start.x) * t
                let y = start.y + (end.y - start.y) * t
                context.fill(
                    Path(CGRect(x: floor(x / 8) * 8, y: floor(y / 8) * 8, width: 8, height: 8)),
                                with: .color(PixelPalette.foam.opacity(0.24))

                )
            }
        }
    }
}
