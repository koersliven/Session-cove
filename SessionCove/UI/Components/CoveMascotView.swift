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
    /// Optional per-provider asset prefix. When `nil` (the default), the
    /// view uses the static Claude assets baked into `MascotImage`. When
    /// the active session is owned by a non-Claude provider (Cursor /
    /// Qoder / QoderWork), callers can pass the provider id and the view
    /// will try `<prefix>_<state>` first, falling back to `claude_<state>`
    /// via `MascotImage.loadMascot`. This keeps existing call sites
    /// unchanged while letting `PetMascotView` swap art when the user is
    /// running Cursor or Qoder.
    var providerPrefix: String? = nil

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
        // Prefer the provider-specific asset chain when a non-default
        // prefix is supplied. The chain falls back to Claude art for
        // states the provider doesn't ship art for, so partial coverage
        // (e.g. only qoder_working.png exists, not qoder_pet_blink.png)
        // degrades gracefully instead of going blank.
        if let prefix = providerPrefix, prefix != "claude" {
            return MascotImage.loadMascot(state: state, prefix: prefix)
        }
        switch state {
        case .working:      return MascotImage.working
        case .sleeping:     return MascotImage.sleeping
        case .attention:    return MascotImage.attention
        case .idle:         return MascotImage.idle
        case .dragged:      return MascotImage.wink
        case .petBlink:     return MascotImage.petBlink
        case .petSip:       return MascotImage.petSip
        case .petBubble:    return MascotImage.petBubble
        case .petCelebrate: return MascotImage.petCelebrate
        }
    }
}
