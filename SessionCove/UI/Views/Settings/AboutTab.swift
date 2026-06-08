import SwiftUI
import AppKit

struct AboutTab: View {
    @ObservedObject private var updater = UpdateChecker.shared

    var body: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 12)

            Image(nsImage: NSApp.applicationIconImage ?? NSImage(named: "NSApplicationIcon") ?? NSImage())
                .resizable()
                .interpolation(.high)
                .frame(width: 64, height: 64)

            VStack(spacing: 4) {
                Text("Session Cove")
                    .font(.title2)
                    .bold()
                Text("v\(versionString)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Inspired by ping-island & Dave the Diver")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 18) {
                Link("GitHub", destination: URL(string: "https://github.com/koersliven/Session-cove")!)
                Link("Issues", destination: URL(string: "https://github.com/koersliven/Session-cove/issues")!)
                Link("Star", destination: URL(string: "https://github.com/koersliven/Session-cove")!)
            }

            Spacer()

            updateSection

            Spacer().frame(height: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    @ViewBuilder
    private var updateSection: some View {
        switch updater.state {
        case .idle, .checking:
            Button("检查更新") { updater.check() }
                .disabled(updater.state == .checking)

        case .upToDate:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("已是最新版本")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .available(let version, let dmgURL, let notes):
            if !updater.dismissed {
                updateCard(version: version, dmgURL: dmgURL, notes: notes)
            } else {
                Button("检查更新") { updater.check() }
            }

        case .downloading(let progress):
            VStack(spacing: 6) {
                ProgressView(value: progress)
                    .frame(width: 200)
                Text("正在下载更新...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .readyToInstall:
            VStack(spacing: 6) {
                ProgressView()
                Text("正在安装，即将重启...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .error(let msg):
            VStack(spacing: 4) {
                Text(msg.contains("安装") ? msg : "检查更新失败（网络问题）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("重试") { updater.check() }
            }
        }
    }

    private func updateCard(version: String, dmgURL: URL, notes: String?) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Text("🆕")
                Text("v\(version) 可用")
                    .font(.system(size: 12, weight: .bold))
            }

            if let notes, !notes.isEmpty {
                Text(notes.prefix(200) + (notes.count > 200 ? "..." : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 12) {
                Button("立即更新") {
                    updater.downloadAndInstall(dmgURL: dmgURL)
                }
                .buttonStyle(.borderedProminent)

                Button("稍后") {
                    updater.dismiss()
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(0.3), lineWidth: 1))
        )
    }

    private var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }
}
