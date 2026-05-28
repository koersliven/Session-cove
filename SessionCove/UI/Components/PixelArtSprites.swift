import AppKit
import SwiftUI

enum PixelMascotState: Sendable {
    case working
    case idle
    case sleeping
    case attention
}

enum PixelPalette {
    static let ocean0 = Color(red: 0.22, green: 0.55, blue: 0.70)
    static let ocean1 = Color(red: 0.26, green: 0.61, blue: 0.75)
    static let ocean2 = Color(red: 0.18, green: 0.49, blue: 0.66)
    static let foam = Color(red: 0.76, green: 0.96, blue: 0.95)
    static let ink = Color(red: 0.02, green: 0.04, blue: 0.08)
    static let hud = Color(red: 0.05, green: 0.09, blue: 0.15)
    static let hudEdge = Color(red: 0.22, green: 0.42, blue: 0.56)
    static let sand = Color(red: 0.86, green: 0.66, blue: 0.34)
    static let sandLight = Color(red: 0.98, green: 0.78, blue: 0.42)
    static let grass = Color(red: 0.22, green: 0.62, blue: 0.34)
    static let grassDark = Color(red: 0.10, green: 0.38, blue: 0.26)
    static let trunk = Color(red: 0.44, green: 0.25, blue: 0.15)
    static let octo = Color(red: 0.96, green: 0.39, blue: 0.13)
    static let octoLight = Color(red: 1.00, green: 0.58, blue: 0.22)
    static let octoDark = Color(red: 0.66, green: 0.18, blue: 0.10)
    static let headphone = Color(red: 0.09, green: 0.56, blue: 0.86)
    static let headphoneDark = Color(red: 0.04, green: 0.20, blue: 0.58)
    static let screen = Color(red: 0.14, green: 0.95, blue: 0.56)
    static let alert = Color(red: 1.0, green: 0.82, blue: 0.22)
    static let coral = Color(red: 1.0, green: 0.38, blue: 0.32)
    static let coralPink = Color(red: 1.0, green: 0.54, blue: 0.65)
    static let kelp = Color(red: 0.14, green: 0.56, blue: 0.36)
    static let jelly = Color(red: 0.74, green: 0.58, blue: 0.96)
    static let seahorse = Color(red: 1.0, green: 0.70, blue: 0.28)
}

struct PixelOceanBackground: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(
                    stops: [
                        .init(color: Color(red: 0.22, green: 0.64, blue: 0.78), location: 0.00),
                        .init(color: Color(red: 0.14, green: 0.45, blue: 0.66), location: 0.50),
                        .init(color: Color(red: 0.05, green: 0.22, blue: 0.38), location: 1.00)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                Canvas { context, size in
                    drawLightColumns(context: &context, size: size)
                    drawWaterTexture(context: &context, size: size)
                    drawBubbles(context: &context, size: size)
                }
                PixelSeaLifeLayer()
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(PixelPalette.ocean0)
        .allowsHitTesting(false)
    }

    private func drawLightColumns(context: inout GraphicsContext, size: CGSize) {
        let columns = [
            (x: size.width * 0.22, width: size.width * 0.10, opacity: 0.11),
            (x: size.width * 0.58, width: size.width * 0.14, opacity: 0.08),
            (x: size.width * 0.82, width: size.width * 0.08, opacity: 0.07)
        ]
        for column in columns {
            var path = Path()
            path.move(to: CGPoint(x: column.x - column.width * 0.35, y: 0))
            path.addLine(to: CGPoint(x: column.x + column.width * 0.35, y: 0))
            path.addLine(to: CGPoint(x: column.x + column.width, y: size.height))
            path.addLine(to: CGPoint(x: column.x - column.width, y: size.height))
            path.closeSubpath()
            context.fill(path, with: .color(PixelPalette.foam.opacity(column.opacity)))
        }
    }

    private func drawWaterTexture(context: inout GraphicsContext, size: CGSize) {
        let unit: CGFloat = 12
        let columns = Int(ceil(size.width / unit))
        let rows = Int(ceil(size.height / unit))
        for row in 0...rows {
            for column in 0...columns {
                let wave = (row * 7 + column * 5) % 31 == 0
                let softPatch = (row * 3 + column * 11) % 59 == 0
                if wave || softPatch {
                    let color = wave ? PixelPalette.foam.opacity(0.22) : PixelPalette.ocean1.opacity(0.26)
                    context.fill(
                        Path(CGRect(x: CGFloat(column) * unit, y: CGFloat(row) * unit, width: unit, height: unit)),
                        with: .color(color)
                    )
                }
            }
        }
    }

    private func drawBubbles(context: inout GraphicsContext, size: CGSize) {
        let bubbles = [
            CGPoint(x: size.width * 0.08, y: size.height * 0.62),
            CGPoint(x: size.width * 0.12, y: size.height * 0.68),
            CGPoint(x: size.width * 0.55, y: size.height * 0.16),
            CGPoint(x: size.width * 0.88, y: size.height * 0.32),
            CGPoint(x: size.width * 0.79, y: size.height * 0.82)
        ]
        for point in bubbles {
            context.stroke(
                Path(CGRect(x: floor(point.x / 8) * 8, y: floor(point.y / 8) * 8, width: 8, height: 8)),
                with: .color(PixelPalette.foam.opacity(0.36)),
                lineWidth: 2
            )
        }
    }
}

struct PixelSeaLifeLayer: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                SeaLifeSprite(kind: .reef)
                    .frame(width: 210, height: 60)
                    .position(x: floor(geo.size.width * 0.14), y: floor(geo.size.height * 0.91))
                    .opacity(0.96)
                SeaLifeSprite(kind: .reef)
                    .frame(width: 168, height: 48)
                    .scaleEffect(x: -1, y: 1)
                    .position(x: floor(geo.size.width * 0.89), y: floor(geo.size.height * 0.90))
                    .opacity(0.88)
                SeaLifeSprite(kind: .kelp)
                    .frame(width: 90, height: 80)
                    .position(x: floor(geo.size.width * 0.48), y: floor(geo.size.height * 0.91))
                    .opacity(0.72)
                SeaLifeSprite(kind: .jellyfish)
                    .frame(width: 100, height: 70)
                    .position(x: floor(geo.size.width * 0.09), y: floor(geo.size.height * 0.38))
                    .opacity(0.92)
                SeaLifeSprite(kind: .jellyfish)
                    .frame(width: 80, height: 56)
                    .position(x: floor(geo.size.width * 0.19), y: floor(geo.size.height * 0.27))
                    .opacity(0.68)
                SeaLifeSprite(kind: .seahorse)
                    .frame(width: 80, height: 95)
                    .position(x: floor(geo.size.width * 0.92), y: floor(geo.size.height * 0.53))
                    .opacity(0.94)
                SeaLifeSprite(kind: .fishSchool)
                    .frame(width: 96, height: 28)
                    .position(x: floor(geo.size.width * 0.70), y: floor(geo.size.height * 0.18))
                    .opacity(0.62)
            }
        }
    }
}

enum SeaLifeKind {
    case jellyfish
    case seahorse
    case reef
    case kelp
    case fishSchool
}

struct SeaLifeSprite: View {
    let kind: SeaLifeKind

    private var rows: [String] {
        switch kind {
        case .jellyfish:
            [
                "........jjjj........",
                "......jJJJJJJj......",
                ".....jJJHHHHJJj.....",
                "....jJHHJJJJHHJj....",
                "....JHHJJJJJJHHJ....",
                "...jJHJJJJJJJJHJj...",
                "...JHHJJJJJJJJHHJ...",
                "...JHHJJJJJJJJHHJ...",
                "....JJHHHHHHHHJJ....",
                ".....TT.TT.TT.T.....",
                "....T..TT..TT..T....",
                "...T...T....T...T...",
                "......T......T......",
                "....T..........T...."
            ]
        case .seahorse:
            [
                "..........SSS...",
                "........SSHHSS..",
                ".......SHHHHHS..",
                "......SHH..HSS..",
                "......SHH.......",
                "......SSHHSS....",
                ".......SSHHHS...",
                "........SHHHS...",
                ".......SSHHHS...",
                "......SSHHSS....",
                ".....SSHHSS.....",
                "....SSHHSS......",
                "...SSHHSS.......",
                "..SSHHSS........",
                "..SHHSS.........",
                "...SSS.....SS...",
                ".........SSHHSS.",
                "........SHHHHSS.",
                ".........SSSS..."
            ]
        case .reef:
            [
                "................C...................P.....",
                ".......C........C.C.................P.P...",
                ".......C.C......CCC.......R........PPP....",
                "....C..CCC..C...CCC......RRR......PPPP.P.",
                "....CCCCCCCCCC..CCC.R...RRRRR...PPPPPPP.",
                "...CCCCCCCCCCCC.CCCRRR.RRRRRRR..PPPPPP..",
                "....CCCCCCCCCC..CCRRRRRRRRRRR....PPPP...",
                "......CCCCCC....RRRRRRRRRRRRR.....PP....",
                "...K....CC...K..RRRRRRRRRRRRR..K....K...",
                "..KKK..BBBB.KKK.BBBBBBBBBBBBBB.KKK..KKK..",
                ".KKKKK.BBBBBKKKKKBBBBBBBBBBBBBKKKKK.KKKK.",
                "KKKKKKBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBKKKKK"
            ]
        case .kelp:
            [
                "......K....K......",
                ".....KKK..KKK.....",
                "......KKKKKK......",
                ".......KKKK.......",
                ".....KKKKKKKK.....",
                "....KKKK..KKKK....",
                "......KKKKKK......",
                ".......KKKK.......",
                ".....KKKKKKKK.....",
                "....KKKK..KKKK....",
                "......KKKKKK......",
                ".......KKKK.......",
                "......KKKKKK......",
                ".......KKKK.......",
                ".......KKKK.......",
                ".......KKKK......."
            ]
        case .fishSchool:
            [
                "..Fff.....Fff...........",
                ".FFFFf...FFFFf..........",
                "..Fff.....Fff....Fff....",
                ".................FFFFf..",
                ".....Fff..........Fff...",
                "....FFFFf...............",
                ".....Fff................"
            ]
        }
    }

    var body: some View {
        PixelGridSprite(rows: rows) { token in
            switch token {
            case "J": PixelPalette.jelly
            case "H": PixelPalette.foam.opacity(0.86)
            case "j": PixelPalette.jelly.opacity(0.62)
            case "T": PixelPalette.jelly.opacity(0.96)
            case "S": PixelPalette.seahorse
            case "C": Color(red: 1.0, green: 0.38, blue: 0.20)
            case "P": Color(red: 1.0, green: 0.46, blue: 0.68)
            case "R": Color(red: 0.96, green: 0.14, blue: 0.12)
            case "B": Color(red: 0.58, green: 0.30, blue: 0.18)
            case "K": Color(red: 0.20, green: 0.78, blue: 0.45)
            case "F": Color(red: 0.50, green: 0.96, blue: 1.0)
            case "f": Color(red: 0.10, green: 0.58, blue: 0.92)
            default: .clear
            }
        }
    }
}

struct PixelHUDPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(8)
            .background {
                PixelBox(fill: PixelPalette.hud.opacity(0.88), edge: PixelPalette.hudEdge.opacity(0.86))
            }
    }
}

struct PixelBox: View {
    var fill: Color
    var edge: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                Rectangle().fill(edge)
                Rectangle().fill(fill).padding(3)
                Rectangle().fill(PixelPalette.ink.opacity(0.32)).frame(width: 3).position(x: w - 1.5, y: h / 2)
                Rectangle().fill(PixelPalette.ink.opacity(0.32)).frame(height: 3).position(x: w / 2, y: h - 1.5)
                Rectangle().fill(fill).frame(width: 5, height: 5).position(x: 2.5, y: 2.5)
                Rectangle().fill(fill).frame(width: 5, height: 5).position(x: w - 2.5, y: 2.5)
                Rectangle().fill(fill).frame(width: 5, height: 5).position(x: 2.5, y: h - 2.5)
                Rectangle().fill(fill).frame(width: 5, height: 5).position(x: w - 2.5, y: h - 2.5)
            }
        }
    }
}

struct PixelIslandSprite: View {
    var mood: IslandMood = .recent

    private let fallbackMap: [String] = [
        ".............................",
        ".............................",
        "....................L........",
        "...................LLL.......",
        "..................LLLLL......",
        "....................T........",
        "...................GTG.......",
        ".............OOOOOGGGG.......",
        "..........OOGGGGGGGGGGO......",
        "........OOGGGGGGGGGGGGGO.....",
        "......OOSSSSSSSSSSSSSSSOO....",
        ".....OOSSSSSSSSSSSSSSSSSOO...",
        "....OOSSSSSSSSRSSSSSSSSSOO...",
        ".....OOSSSSSSSSSSSSSSSSOO....",
        "......OOSSSSSSSSSSSSSSOO.....",
        "........OOOOOOOOOOOOOOO......",
        "............................."
    ]

    var body: some View {
        PixelGridSprite(rows: fallbackMap) { token in
            switch token {
            case "S": mood.sand
            case "G": mood.grass
            case "L": mood.palm
            case "T": PixelPalette.trunk
            case "R": mood.rock
            case "O": PixelPalette.ink.opacity(0.70)
            default: .clear
            }
        }
        .aspectRatio(29 / 17, contentMode: .fit)
    }
}

struct PixelOctopusSprite: View {
    var state: PixelMascotState = .working

    private var fallbackMap: [String] {
        switch state {
        case .working, .idle, .attention:
            [
                "................",
                ".....BBBBBB.....",
                "....BHHHHHHB....",
                "...BOOOOOOOOB...",
                "...BOLOOOLOOB...",
                "...BOOEEOOOB....",
                "....OOOOOO......",
                "...DOOOOOOD.....",
                "..DODODODOD.....",
                "......MMMM......",
                "......MSSM......",
                "......MSSM......",
                "................"
            ]
        case .sleeping:
            [
                "...........Z....",
                ".....BBBBBB.Z...",
                "....BHHHHHHB....",
                "...BOOOOOOOOB...",
                "...BO-OOO-OB....",
                "...BOOOOOOOB....",
                "....OOOOOO......",
                "...DOOOOOOD.....",
                "..DODODODOD.....",
                "................",
                "................",
                "................",
                "................"
            ]
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            PixelGridSprite(rows: fallbackMap) { token in
                switch token {
                case "O": PixelPalette.octo
                case "L": PixelPalette.octoLight
                case "D": PixelPalette.octoDark
                case "H": PixelPalette.headphone
                case "B": PixelPalette.headphoneDark
                case "E": PixelPalette.ink.opacity(0.84)
                case "M": PixelPalette.ink
                case "S": PixelPalette.screen
                case "-": PixelPalette.ink.opacity(0.76)
                case "Z": .white.opacity(0.82)
                default: .clear
                }
            }
            .aspectRatio(16 / 13, contentMode: .fit)

            if state == .attention {
                Text("!")
                    .font(.system(size: 15, weight: .black, design: .monospaced))
                    .foregroundStyle(PixelPalette.alert)
                    .shadow(color: PixelPalette.ink, radius: 0, x: 1, y: 1)
                    .offset(x: -4, y: 0)
            }
        }
    }
}

struct PixelGridSprite: View {
    let rows: [String]
    let color: (Character) -> Color

    var body: some View {
        GeometryReader { geo in
            let columns = rows.map(\.count).max() ?? 1
            let unit = max(1, floor(min(geo.size.width / CGFloat(columns), geo.size.height / CGFloat(rows.count))))
            let xOffset = floor((geo.size.width - CGFloat(columns) * unit) / 2)
            let yOffset = floor((geo.size.height - CGFloat(rows.count) * unit) / 2)
            ZStack(alignment: .topLeading) {
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    ForEach(Array(Array(row).enumerated()), id: \.offset) { columnIndex, token in
                        let fill = color(token)
                        if fill != .clear {
                            let x = xOffset + CGFloat(columnIndex) * unit
                            let y = yOffset + CGFloat(rowIndex) * unit
                            Rectangle()
                                .fill(PixelPalette.ink.opacity(0.18))
                                .frame(width: unit, height: unit)
                                .offset(x: x + 1, y: y + 1)
                            Rectangle()
                                .fill(fill)
                                .frame(width: unit, height: unit)
                                .offset(x: x, y: y)
                        }
                    }
                }
            }
        }
    }
}

enum IslandMood: Sendable {
    case active
    case recent
    case archived

    var sand: Color {
        switch self {
        case .active: PixelPalette.sandLight
        case .recent: PixelPalette.sand
        case .archived: Color(red: 0.50, green: 0.49, blue: 0.42)
        }
    }

    var grass: Color {
        switch self {
        case .active: PixelPalette.grass
        case .recent: Color(red: 0.20, green: 0.52, blue: 0.30)
        case .archived: Color(red: 0.23, green: 0.33, blue: 0.30)
        }
    }

    var palm: Color {
        switch self {
        case .archived: Color(red: 0.20, green: 0.34, blue: 0.26)
        default: PixelPalette.grassDark
        }
    }

    var waterEdge: Color { PixelPalette.foam.opacity(self == .archived ? 0.26 : 0.62) }
    var rock: Color { Color(red: 0.38, green: 0.39, blue: 0.42) }

    var saturation: Double {
        switch self {
        case .active: 1.08
        case .recent: 1.0
        case .archived: 0.72
        }
    }

    var brightness: Double {
        switch self {
        case .active: 0.02
        case .recent: 0
        case .archived: -0.08
        }
    }
}
