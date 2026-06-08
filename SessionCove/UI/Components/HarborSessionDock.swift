import SwiftUI

struct HarborSessionDock: View {
    let island: ProjectIsland
    let onSessionTap: (SessionRecord) -> Void
    let onResume: (SessionRecord) -> Void
    let onDelete: (SessionRecord) -> Void
    var onNewSession: (() -> Void)? = nil

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
            Text(island.displayName)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)

            Text("·")
                .foregroundStyle(.white.opacity(0.3))

            Text("\(island.totalCount) sessions")
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))

            Spacer()

            if isSelecting {
                Button {
                    for id in selected {
                        if let session = island.sessions.first(where: { $0.id == id }) {
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

                if let onNewSession {
                    Button(action: onNewSession) {
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
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var sessionScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                ForEach(dockSessions) { session in
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
                if island.totalCount > 8 {
                    HiddenSessionsCard(count: island.totalCount - 8)
                }
            }
            .padding(.vertical, 2)
        }
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
            .fill(Color(red: 0.03, green: 0.08, blue: 0.14).opacity(0.85))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(PixelPalette.foam.opacity(0.12), lineWidth: 1)
            )
    }

    private var dockSessions: [SessionRecord] {
        island.sessions
            .sorted { lhs, rhs in
                let lp = statusPriority(lhs.status)
                let rp = statusPriority(rhs.status)
                if lp != rp { return lp < rp }
                return lhs.lastModified > rhs.lastModified
            }
            .prefix(8)
            .map { $0 }
    }

    private func statusPriority(_ status: SessionStatus) -> Int {
        switch status {
        case .active: 0
        case .recentlyIdle: 1
        case .archived: 2
        }
    }
}

struct HarborSessionDockCard: View {
    let session: SessionRecord
    let onTap: () -> Void
    let onResume: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var isRenaming = false
    @State private var renamingText = ""

    private var customName: String? {
        SessionNameStore.shared.name(for: session.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Name + rename button
            HStack(spacing: 0) {
                Button {
                    renamingText = customName ?? ""
                    isRenaming = true
                } label: {
                    HStack(spacing: 3) {
                        Text(customName ?? "—")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(customName != nil ? .white : .white.opacity(0.3))
                            .lineLimit(1)
                        Image(systemName: "pencil.line")
                            .font(.system(size: 8))
                            .foregroundStyle(PixelPalette.foam.opacity(0.6))
                    }
                }
                .buttonStyle(.plain)
                Spacer()
            }

            // Status + time
            HStack(spacing: 5) {
                SessionDot(status: session.status)
                Text(session.relativeTime)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }

            // AI summary — 3 lines
            Text(session.displayTitle)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .topLeading)
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)

            // Action row - button handles its own click, no parent gesture interference
            HStack {
                if let branch = session.gitBranch {
                    Text(branch)
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundStyle(PixelPalette.foam.opacity(0.6))
                        .lineLimit(1)
                        .onTapGesture(perform: onTap)
                }
                Spacer()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onTap)
                Button(action: onResume) {
                    HStack(spacing: 3) {
                        Text("▶")
                            .font(.system(size: 9))
                        Text(buttonLabel)
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(buttonColor))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .frame(width: 156, height: 120)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color(red: 0.06, green: 0.16, blue: 0.26) : Color(red: 0.04, green: 0.11, blue: 0.19))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isHovered ? PixelPalette.foam.opacity(0.3) : PixelPalette.foam.opacity(0.1), lineWidth: 1)
                )
        )
        .onHover { isHovered = $0 }
        .contextMenu {
            Button(action: {
                renamingText = customName ?? ""
                isRenaming = true
            }) {
                Label("重命名", systemImage: "pencil")
            }
            Button(role: .destructive, action: onDelete) {
                Label("Move to Trash", systemImage: "trash")
            }
        }
        .popover(isPresented: $isRenaming) {
            VStack(spacing: 8) {
                Text("重命名")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)
                TextField("自定义名称", text: $renamingText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                HStack(spacing: 8) {
                    Button("取消") { isRenaming = false }
                        .font(.system(size: 10))
                    Button("保存") {
                        SessionNameStore.shared.setName(
                            renamingText.isEmpty ? nil : renamingText,
                            for: session.id
                        )
                        isRenaming = false
                    }
                    .font(.system(size: 10, weight: .bold))
                }
            }
            .padding(12)
        }
    }

    private var buttonLabel: String {
        switch session.status {
        case .active: "OPEN"
        case .recentlyIdle: "RESUME"
        case .archived: "RUN"
        }
    }

    private var buttonColor: Color {
        switch session.status {
        case .active: Color(red: 0.10, green: 0.45, blue: 0.30)
        case .recentlyIdle: Color(red: 0.40, green: 0.30, blue: 0.12)
        case .archived: Color(red: 0.12, green: 0.34, blue: 0.52)
        }
    }
}

struct HiddenSessionsCard: View {
    let count: Int

    var body: some View {
        VStack(spacing: 4) {
            Text("+\(count)")
                .font(.system(size: 14, weight: .black, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
            Text("more")
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(width: 64, height: 120)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}
