import SwiftUI

enum MascotScale: Sendable {
    case pet
    case compact
    case ping
    case shelf
    case row
    case island
    case approval

    var size: CGSize {
        switch self {
        case .pet: CGSize(width: 48, height: 48)
        case .compact: CGSize(width: 42, height: 38)
        case .ping: CGSize(width: 38, height: 34)
        case .shelf: CGSize(width: 50, height: 46)
        case .row: CGSize(width: 24, height: 22)
        case .island: CGSize(width: 72, height: 64)
        case .approval: CGSize(width: 52, height: 48)
        }
    }
}

struct CoveMascotView: View {
    let state: PixelMascotState
    var scale: MascotScale = .shelf
    var grounded: Bool = false

    var body: some View {
        ZStack(alignment: .bottom) {
            mascotContent
                .frame(width: scale.size.width, height: scale.size.height)

            if grounded {
                Ellipse()
                    .fill(PixelPalette.ink.opacity(0.18))
                    .frame(width: scale.size.width * 0.6, height: 4)
                    .offset(y: 2)
            }
        }
    }

    @ViewBuilder
    private var mascotContent: some View {
        if let image = mascotImage {
            Image(nsImage: image)
                .resizable()
                .interpolation(.none)
                .aspectRatio(contentMode: .fit)
        } else {
            PixelOctopusSprite(state: state)
        }
    }

    private var mascotImage: NSImage? {
        switch state {
        case .working: MascotImage.working
        case .sleeping: MascotImage.sleeping
        case .attention: MascotImage.attention
        case .idle: MascotImage.idle
        case .dragged: MascotImage.wink
        }
    }
}
