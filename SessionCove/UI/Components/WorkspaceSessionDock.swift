import SwiftUI

struct WorkspaceSessionDock: View {
    let workspace: Workspace
    let onSessionTap: (SessionRecord) -> Void
    let onResume: (SessionRecord) -> Void
    let onDelete: (SessionRecord) -> Void
    let onNewSession: (String) -> Void

    @State private var isSelecting = false
    @State private var selected: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            dockHeader
            sessionScroll
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(dockBackground)
    }

    private var dockHeader: some View {
        HStack(spacing: 6) {
            Text(workspace.name)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(red: 0.90, green: 0.72, blue: 0.20))
                .lineLimit(1)

            Text("·")
                .foregroundStyle(.white.opacity(0.3))

            Text("\(workspace.totalCount) sessions")
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))

            Spacer()

            if isSelecting {
                Button {
                    for id in selected {
                        if let session = workspace.sessions.first(where: { $0.id == id }) {
                            onDelete(session)
                        }
                    }
                    selected.removeAll()
                    isSelecting = false
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 8))
                        Text("\(selected.count)")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(PixelPalette.coral.opacity(selected.isEmpty ? 0.4 : 0.9))
                            .overlay(Capsule().stroke(PixelPalette.coral, lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)
                .disabled(selected.isEmpty)

                Button {
                    selected.removeAll()
                    isSelecting = false
                } label: {
                    Text("✕")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    isSelecting = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 9, weight: .bold))
                        Text("SELECT")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.15, green: 0.20, blue: 0.30))
                            .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)

                Menu {
                    ForEach(workspace.folderPaths, id: \.self) { path in
                        Button((path as NSString).lastPathComponent) {
                            onNewSession(path)
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text("+")
                            .font(.system(size: 11, weight: .black))
                        Text("NEW")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.10, green: 0.45, blue: 0.30))
                            .overlay(Capsule().stroke(PixelPalette.grass.opacity(0.5), lineWidth: 1))
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    private var sessionScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                if workspace.sessions.isEmpty {
                    emptyCard
                } else {
                    ForEach(workspace.sessions) { session in
                        if isSelecting {
                            selectableCard(for: session)
                        } else {
                            HarborSessionDockCard(
                                session: session,
                                onTap: { onSessionTap(session) },
                                onResume: { onResume(session) },
                                onDelete: { onDelete(session) }
                            )
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var emptyCard: some View {
        VStack(spacing: 6) {
            Text("No sessions yet")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
            Text("Use + NEW to start")
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.white.opacity(0.25))
        }
        .frame(width: 156, height: 120)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func selectableCard(for session: SessionRecord) -> some View {
        let isSelected = selected.contains(session.id)
        return HarborSessionDockCard(
            session: session,
            onTap: {
                if isSelected {
                    selected.remove(session.id)
                } else {
                    selected.insert(session.id)
                }
            },
            onResume: {},
            onDelete: {}
        )
        .overlay(alignment: .topLeading) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(isSelected ? PixelPalette.foam : .white.opacity(0.4))
                .padding(6)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? PixelPalette.foam.opacity(0.6) : .clear, lineWidth: 2)
        )
    }

    @ViewBuilder
    private var dockBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(red: 0.05, green: 0.08, blue: 0.12).opacity(0.85))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(red: 0.90, green: 0.72, blue: 0.20).opacity(0.15), lineWidth: 1)
            )
    }
}
