import SwiftUI

struct SessionPebbleRow: View {
    let session: SessionRecord
    var isAttention: Bool = false
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                // Pebble marker
                pebbleMarker

                Text(session.displayTitle)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)

                Spacer()

                Text(session.relativeTime)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(pebbleBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var pebbleMarker: some View {
        ZStack {
            Capsule()
                .fill(pebbleColor)
                .frame(width: 14, height: 8)

            if isAttention {
                Circle()
                    .fill(PixelPalette.alert)
                    .frame(width: 4, height: 4)
            } else {
                Circle()
                    .fill(statusColor)
                    .frame(width: 4, height: 4)
            }
        }
    }

    @ViewBuilder
    private var pebbleBackground: some View {
        if isHovered {
            Capsule()
                .fill(PixelPalette.sand.opacity(0.12))
        }
    }

    private var pebbleColor: Color {
        if isAttention { return PixelPalette.alert.opacity(0.25) }
        switch session.status {
        case .active: return PixelPalette.grass.opacity(0.2)
        case .recentlyIdle: return PixelPalette.sand.opacity(0.15)
        case .archived: return .white.opacity(0.06)
        }
    }

    private var statusColor: Color {
        switch session.status {
        case .active: .green
        case .recentlyIdle: PixelPalette.sand
        case .archived: .gray.opacity(0.4)
        }
    }
}
