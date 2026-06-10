import SwiftUI
import AppKit

struct AboutTab: View {
    @ObservedObject private var updater = UpdateChecker.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage ?? NSImage(named: "NSApplicationIcon") ?? NSImage())
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 56, height: 56)

                VStack(spacing: 4) {
                    Text("Session Cove")
                        .font(.title3)
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

                Divider()

                updateSection

                diagnosticSection
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Diagnostics

    @State private var diagnosticDescription = ""
    @State private var diagnosticStatus: String?
    @State private var isExporting = false

    private var diagnosticSection: some View {
        VStack(spacing: 8) {
            Divider().padding(.vertical, 4)

            TextField("描述你遇到的问题（可选）", text: $diagnosticDescription)
                .textFieldStyle(.roundedBorder)
                .font(.caption)

            Button {
                isExporting = true
                diagnosticStatus = nil
                Task {
                    let result = await DiagnosticsExporter.shared.export(
                        userDescription: diagnosticDescription
                    )
                    isExporting = false
                    switch result {
                    case .issueCreated(let url):
                        diagnosticStatus = "✅ Issue 已创建: \(url)"
                        NSWorkspace.shared.open(URL(string: url)!)
                    case .savedLocally(let path):
                        diagnosticStatus = "📁 已保存到 \(path)\n请在浏览器中手动提交 Issue"
                    case .error(let msg):
                        diagnosticStatus = "❌ \(msg)"
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    if isExporting {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "ladybug.fill")
                    }
                    Text("上报问题")
                }
            }
            .disabled(isExporting)

            if let status = diagnosticStatus {
                Text(status)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
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
                DisclosureGroup("更新日志") {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .font(.caption)
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
