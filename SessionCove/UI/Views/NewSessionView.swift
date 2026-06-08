import SwiftUI
import AppKit

struct NewSessionView: View {
    @Bindable var viewModel: CoveViewModel
    var onDismiss: () -> Void = {}

    @State private var selectedPath: String = ""

    var body: some View {
        VStack(spacing: 14) {
            header
            instructions
            folderSection
            Spacer(minLength: 0)
            startButton
        }
        .padding(16)
        .frame(width: 340, height: 240)
        .background(Color(red: 0.04, green: 0.09, blue: 0.16))
    }

    private var header: some View {
        HStack {
            Text("NEW SESSION")
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundStyle(PixelPalette.foam)
            Spacer()
            Button { onDismiss() } label: {
                Text("✕")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
    }

    private var instructions: some View {
        Text("选择一个项目文件夹，Claude 将在其中启动。")
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(.white.opacity(0.4))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var folderSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("项目文件夹")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))

            if selectedPath.isEmpty {
                Button { pickFolder() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 10))
                        Text("Select folder")
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
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(PixelPalette.foam.opacity(0.6))
                    Text((selectedPath as NSString).lastPathComponent)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                    Spacer()
                    Button { selectedPath = "" } label: {
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
        }
    }

    private var startButton: some View {
        Button {
            guard !selectedPath.isEmpty else { return }
            SessionResumer.launchNew(projectPath: selectedPath)
            CoveSoundManager.shared.play(.bubblePop)
            onDismiss()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "play.fill")
                    .font(.system(size: 9))
                Text("START SESSION")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(red: 0.10, green: 0.45, blue: 0.30))
            )
        }
        .buttonStyle(.plain)
        .disabled(selectedPath.isEmpty)
        .opacity(selectedPath.isEmpty ? 0.4 : 1.0)
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.message = "Select a project folder to start Claude in"
        panel.prompt = "Select"
        let response = panel.runModal()
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.isVisible {
            window.orderFrontRegardless()
        }
        guard response == .OK, let url = panel.url else { return }
        selectedPath = url.path
    }
}
