import SwiftUI

struct ProjectIslandView: View {
    let island: ProjectIsland
    var scale: CGFloat = 1.0
    var pendingRequest: HookPermissionRequest?

    private var hasPendingPermission: Bool {
        guard let pendingRequest else { return false }
        return island.path == pendingRequest.projectPath
    }

    private var mood: IslandMood {
        if island.activeCount > 0 { return .active }
        if island.recentCount > 0 { return .recent }
        return .archived
    }

    var body: some View {
        VStack(spacing: 5 * scale) {
            ZStack {
                if hasPendingPermission {
                    PixelAttentionRing()
                        .frame(width: 420 * scale, height: 210 * scale)
                        .offset(y: 14 * scale)
                }

                PixelIslandSprite(mood: mood)
                    .frame(width: 410 * scale, height: 200 * scale)
                    .offset(y: 16 * scale)

                mascotsOnIsland
            }
            .frame(width: 430 * scale, height: 238 * scale)

            Text(island.displayName.uppercased())
                .font(.system(size: max(10, 11 * scale), weight: .black, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 7 * scale)
                .padding(.vertical, 3 * scale)
                .background { PixelBox(fill: PixelPalette.hud.opacity(0.86), edge: PixelPalette.hudEdge.opacity(0.78)) }

            HStack(spacing: 8 * scale) {
                if island.activeCount > 0 { pip(PixelPalette.grass, island.activeCount) }
                if island.recentCount > 0 { pip(PixelPalette.sand, island.recentCount) }
                pip(.white.opacity(0.72), island.totalCount)
            }
        }
        .contentShape(Rectangle())
    }

    private var mascotsOnIsland: some View {
        let hasLead = island.totalCount > 0
        return ZStack {
            if hasLead {
                let isActive = island.activeCount > 0
                let isRecent = !isActive && island.recentCount > 0
                let anchor = MascotGroundAnchor(x: 215, groundY: 150)
                GroundedMascot(
                    active: isActive,
                    archived: !isActive && !isRecent,
                    size: 48 * scale,
                    stateOverride: hasPendingPermission ? .attention : nil,
                    facingLeft: false
                )
                .position(
                    x: anchor.x * scale,
                    y: (anchor.groundY - 48 * 0.46) * scale
                )
                .zIndex(anchor.groundY)
            }

            if island.totalCount > 1 {
                crewBadge("+\(island.totalCount - 1)")
                    .position(x: 290 * scale, y: 118 * scale)
            }
        }
        .frame(width: 430 * scale, height: 238 * scale)
    }

    private func mascotAnchor(index: Int, count: Int) -> MascotGroundAnchor {
        let positions: [MascotGroundAnchor]
        switch count {
        case 1:
            positions = [MascotGroundAnchor(x: 215, groundY: 150)]
        case 2:
            positions = [MascotGroundAnchor(x: 170, groundY: 151), MascotGroundAnchor(x: 260, groundY: 152)]
        case 3:
            positions = [MascotGroundAnchor(x: 150, groundY: 154), MascotGroundAnchor(x: 215, groundY: 145), MascotGroundAnchor(x: 280, groundY: 155)]
        default:
            positions = [
                MascotGroundAnchor(x: 132, groundY: 158),
                MascotGroundAnchor(x: 185, groundY: 148),
                MascotGroundAnchor(x: 245, groundY: 149),
                MascotGroundAnchor(x: 298, groundY: 159)
            ]
        }
        return positions[min(index, positions.count - 1)]
    }

    private func crewBadge(_ title: String) -> some View {
        Text(title)
            .font(.system(size: max(9, 10 * scale), weight: .black, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 7 * scale)
            .padding(.vertical, 4 * scale)
            .background { PixelBox(fill: Color(red: 0.10, green: 0.24, blue: 0.32).opacity(0.94), edge: PixelPalette.foam.opacity(0.54)) }
    }

    private struct MascotGroundAnchor {
        let x: CGFloat
        let groundY: CGFloat
    }

    private func pip(_ color: Color, _ count: Int) -> some View {
        HStack(spacing: 4 * scale) {
            Rectangle()
                .fill(color)
                .frame(width: 8 * scale, height: 8 * scale)
            Text("\(count)")
                .font(.system(size: max(9, 9 * scale), weight: .black, design: .monospaced))
                .foregroundStyle(color)
        }
    }
}

struct GroundedMascot: View {
    let active: Bool
    let archived: Bool
    let size: CGFloat
    var stateOverride: PixelMascotState?
    var facingLeft: Bool

    var body: some View {
        ZStack {
            PixelFootShadow()
                .frame(width: size * 0.78, height: size * 0.20)
                .offset(y: size * 0.43)

            PixelFootContact()
                .frame(width: size * 0.54, height: size * 0.12)
                .offset(y: size * 0.47)

            AnimatedMascot(
                active: active,
                archived: archived,
                size: size,
                stateOverride: stateOverride
            )
            .scaleEffect(x: facingLeft ? -1 : 1, y: 1)
            .offset(y: -size * 0.03)
        }
        .frame(width: size, height: size)
    }
}

struct PixelFootShadow: View {
    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let unit = max(2, floor(min(size.width, size.height) / 4))
                let rects = [
                    CGRect(x: unit, y: unit, width: size.width - unit * 2, height: unit * 2),
                    CGRect(x: unit * 2, y: 0, width: size.width - unit * 4, height: unit),
                    CGRect(x: unit * 2, y: unit * 3, width: size.width - unit * 4, height: unit)
                ]
                for rect in rects {
                    context.fill(Path(rect), with: .color(PixelPalette.ink.opacity(0.24)))
                }
            }
        }
    }
}

struct PixelFootContact: View {
    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let unit = max(2, floor(size.height / 2))
                let y = floor(size.height / 2)
                context.fill(
                    Path(CGRect(x: unit, y: y, width: size.width - unit * 2, height: unit)),
                    with: .color(PixelPalette.grassDark.opacity(0.68))
                )
                context.fill(
                    Path(CGRect(x: unit * 2, y: y + unit, width: size.width - unit * 4, height: unit)),
                    with: .color(PixelPalette.sand.opacity(0.62))
                )
            }
        }
    }
}

struct PixelAttentionRing: View {
    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let unit: CGFloat = 8
                let columns = Int(size.width / unit)
                let rows = Int(size.height / unit)
                for x in 0..<columns {
                    context.fill(Path(CGRect(x: CGFloat(x) * unit, y: 0, width: unit, height: unit)), with: .color(PixelPalette.alert.opacity(0.72)))
                    context.fill(Path(CGRect(x: CGFloat(x) * unit, y: CGFloat(rows - 1) * unit, width: unit, height: unit)), with: .color(PixelPalette.alert.opacity(0.72)))
                }
                for y in 0..<rows {
                    context.fill(Path(CGRect(x: 0, y: CGFloat(y) * unit, width: unit, height: unit)), with: .color(PixelPalette.alert.opacity(0.72)))
                    context.fill(Path(CGRect(x: CGFloat(columns - 1) * unit, y: CGFloat(y) * unit, width: unit, height: unit)), with: .color(PixelPalette.alert.opacity(0.72)))
                }
            }
        }
    }
}
