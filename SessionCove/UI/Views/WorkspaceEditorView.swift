import SwiftUI
import AppKit

struct WorkspaceEditorView: View {
    @Bindable var viewModel: CoveViewModel
    var editingId: String? = nil
    var onDismiss: () -> Void = {}

    @State private var name: String = ""
    @State private var parentPath: String = ""
    @State private var repoPaths: [String] = []

    private var isEditing: Bool { editingId != nil }

    private var workspacePath: String {
        guard !parentPath.isEmpty, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return "" }
        return (parentPath as NSString).appendingPathComponent(name.trimmingCharacters(in: .whitespaces))
    }

    var body: some View {
        VStack(spacing: 14) {
            header
            nameField
            parentDirectorySection
            reposSection
            Spacer(minLength: 0)
            workspacePathPreview
            confirmButton
        }
        .padding(16)
        .frame(width: 360, height: 420)
        .background(Color(red: 0.04, green: 0.09, blue: 0.16))
        .onAppear {
            if let id = editingId,
               let ws = WorkspaceStore.shared.workspaces.first(where: { $0.id == id }) {
                name = ws.name
                let wsPath = ws.folderPaths.first ?? ""
                parentPath = (wsPath as NSString).deletingLastPathComponent
                repoPaths = Array(ws.folderPaths.dropFirst())
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(isEditing ? "EDIT WORKSPACE" : "NEW WORKSPACE")
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundStyle(Color(red: 0.90, green: 0.72, blue: 0.20))
            Spacer()
            Button { onDismiss() } label: {
                Text("✕")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Name

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("名称")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
            TextField("e.g. my-project", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white.opacity(0.06))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.2), lineWidth: 1))
                )
        }
    }

    // MARK: - Parent Directory

    private var parentDirectorySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("父目录")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
            Text("将在此目录下以 Workspace 名称创建新文件夹，Claude 会话将在其中运行。")
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
                .fixedSize(horizontal: false, vertical: true)

            if parentPath.isEmpty {
                Button { pickParentDirectory() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 10))
                        Text("Select parent folder")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(PixelPalette.foam)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(PixelPalette.foam.opacity(0.08))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(PixelPalette.foam.opacity(0.3), lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)
            } else {
                folderRow(path: parentPath, badge: nil) {
                    parentPath = ""
                }
            }
        }
    }

    // MARK: - Repos

    private var reposSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("代码仓库")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Button { pickRepos() } label: {
                    HStack(spacing: 2) {
                        Text("+")
                            .font(.system(size: 10, weight: .black))
                        Text("ADD")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.15, green: 0.20, blue: 0.30))
                            .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)
            }

            Text("选择的代码仓库将以快捷方式链接到 Workspace 文件夹中，Claude 可以直接访问所有代码。")
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
                .fixedSize(horizontal: false, vertical: true)

            if repoPaths.isEmpty {
                Text("未添加仓库 — 之后也可以再添加")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.2))
                    .padding(.vertical, 4)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(repoPaths, id: \.self) { path in
                            folderRow(path: path, badge: nil) {
                                repoPaths.removeAll { $0 == path }
                            }
                        }
                    }
                }
                .frame(maxHeight: 80)
            }
        }
    }

    // MARK: - Folder Row

    private func folderRow(path: String, badge: String?, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.system(size: 9))
                .foregroundStyle(PixelPalette.foam.opacity(0.6))
            Text((path as NSString).lastPathComponent)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(.white.opacity(0.04))
        )
    }

    // MARK: - Path Preview

    @ViewBuilder
    private var workspacePathPreview: some View {
        if !workspacePath.isEmpty {
            HStack(spacing: 4) {
                Text("→")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.3))
                Text(workspacePath)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    // MARK: - Confirm

    private var confirmButton: some View {
        Button { confirm() } label: {
            HStack(spacing: 6) {
                Image(systemName: "play.fill")
                    .font(.system(size: 9))
                Text(isEditing ? "SAVE" : "CREATE & START")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
            }
            .foregroundStyle(Color(red: 0.04, green: 0.09, blue: 0.16))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(red: 0.90, green: 0.72, blue: 0.20))
            )
        }
        .buttonStyle(.plain)
        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || parentPath.isEmpty)
        .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty || parentPath.isEmpty ? 0.4 : 1.0)
    }

    // MARK: - Actions

    private func pickParentDirectory() {
        guard let path = runFolderPicker(message: "Select parent directory for the workspace") else { return }
        parentPath = path
    }

    private func pickRepos() {
        guard let paths = runFolderPicker(message: "Select repos to include", multiple: true) else { return }
        for path in paths where !repoPaths.contains(path) {
            repoPaths.append(path)
        }
    }

    private func runFolderPicker(message: String, multiple: Bool = false) -> [String]? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = multiple
        panel.showsHiddenFiles = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.message = message
        panel.prompt = "Select"
        let response = panel.runModal()
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.isVisible {
            window.orderFrontRegardless()
        }
        guard response == .OK, !panel.urls.isEmpty else { return nil }
        return panel.urls.map(\.path)
    }

    private func runFolderPicker(message: String) -> String? {
        runFolderPicker(message: message, multiple: false)?.first
    }

    private func syncSymlinks(workspaceDir: String, repos: [String]) {
        let fm = FileManager.default
        for repoPath in repos {
            let repoName = (repoPath as NSString).lastPathComponent
            let linkPath = (workspaceDir as NSString).appendingPathComponent(repoName)
            // Skip if already exists (symlink or real dir)
            if fm.fileExists(atPath: linkPath) { continue }
            try? fm.createSymbolicLink(atPath: linkPath, withDestinationPath: repoPath)
        }
    }

    private func confirm() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, !parentPath.isEmpty else { return }

        let wsDir = workspacePath
        let allFolders = [wsDir] + repoPaths

        if let id = editingId {
            viewModel.editWorkspace(id: id, name: trimmedName, folderPaths: allFolders)
            syncSymlinks(workspaceDir: wsDir, repos: repoPaths)
        } else {
            // Create the workspace directory
            try? FileManager.default.createDirectory(
                atPath: wsDir,
                withIntermediateDirectories: true
            )
            // Symlink repos into workspace directory
            syncSymlinks(workspaceDir: wsDir, repos: repoPaths)
            viewModel.createWorkspace(name: trimmedName, folderPaths: allFolders)
            // Launch Claude in the new workspace directory
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if let ws = WorkspaceStore.shared.workspaces.last(where: { $0.name == trimmedName }) {
                    viewModel.newSessionInWorkspace(
                        Workspace(data: ws),
                        folderPath: wsDir
                    )
                }
            }
        }
        onDismiss()
    }
}
