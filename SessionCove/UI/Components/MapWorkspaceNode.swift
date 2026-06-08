import SwiftUI

struct MapWorkspaceNode: View {
    let workspace: Workspace
    var isSelected: Bool = false
    var compact: Bool = false
    let onTap: () -> Void

    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @State private var isHovered = false
    @State private var spotlightWidth: CGFloat = 0

    private var mood: IslandMood {
        if workspace.activeCount > 0 { return .active }
        if workspace.recentCount > 0 { return .recent }
        return .archived
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                ZStack(alignment: .center) {
                    if isSelected {
                        Ellipse()
                            .fill(
                                RadialGradient(
                                    colors: [Color(red: 0.85, green: 0.65, blue: 0.2).opacity(0.5), .clear],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 48
                                )
                            )
                            .frame(width: 96, height: 40)
                            .offset(y: 20)
                            .opacity(spotlightWidth)
                    }

                    PixelIslandSprite(mood: mood)
                        .saturation(mood.saturation)
                        .brightness(isSelected ? mood.brightness + 0.08 : mood.brightness)

                    if workspace.activeCount > 0 && !compact {
                        ActiveIslandBubbles()
                            .offset(x: -20, y: -16)
                        ActiveIslandBubbles()
                            .offset(x: 18, y: -12)
                    }
                }

                HStack(spacing: 4) {
                    Text("WS")
                        .font(.system(size: 7, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Color(red: 0.20, green: 0.12, blue: 0.0))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(Color(red: 0.90, green: 0.72, blue: 0.20))
                                .overlay(Capsule().stroke(Color(red: 0.70, green: 0.50, blue: 0.10).opacity(0.6), lineWidth: 0.5))
                        )

                    Text(workspace.name)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(isSelected ? 1.0 : 0.72))
                        .lineLimit(1)
                        .shadow(color: isSelected ? Color(red: 0.9, green: 0.75, blue: 0.3).opacity(0.8) : .clear, radius: 4)
                }
                .padding(.top, 2)
            }
            .scaleEffect(compact ? 1.0 : (isHovered ? 1.12 : (isSelected ? 1.22 : 1.0)))
            .animation(compact ? nil : .interpolatingSpring(stiffness: 200, damping: 8), value: isSelected)
            .animation(compact ? nil : .snappy(duration: 0.14), value: isHovered)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            guard !compact else { return }
            isHovered = hovering
        }
        .onChange(of: isSelected) { _, selected in
            if selected {
                withAnimation(.easeOut(duration: 0.4)) { spotlightWidth = 1 }
            } else {
                withAnimation(.easeIn(duration: 0.2)) { spotlightWidth = 0 }
            }
        }
        .contextMenu {
            if let onEdit {
                Button(action: onEdit) {
                    Label("Edit Workspace", systemImage: "pencil")
                }
            }
            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete Workspace", systemImage: "trash")
                }
            }
        }
    }
}
