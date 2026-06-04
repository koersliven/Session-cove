import SwiftUI

/// Settings tab that exposes the per-provider enable/disable toggles plus a
/// per-row install status indicator.
///
/// Wiring contract (step 10):
///   * Toggles bind to `CoveSettings.shared.enabledProviders` via a
///     `Set<String>`-aware `Binding`. Flipping the toggle posts
///     `.coveEnabledProvidersDidChange`, which `WindowManager` observes and
///     fans out to `ClaudePermissionHook.installFor<Provider>` /
///     `uninstall(providerId:)`.
///   * The Claude row's toggle is `.disabled(true)` because Claude is the
///     mandatory baseline — the model also re-inserts `"claude"` if it
///     somehow gets removed (defensive guard in `CoveSettings`).
///   * "已安装" / "未安装" status comes from
///     `ClaudePermissionHook.isInstalled(providerId:)`, which substring-
///     matches the bridge script path in the provider's settings file.
struct AIFrameworksTab: View {
    @EnvironmentObject var settings: CoveSettings

    /// Cached snapshot of `isInstalled` per provider id. Refreshed each
    /// time the view appears or `enabledProviders` changes — calling
    /// `isInstalled` directly inside `body` would re-read the JSON file
    /// on every view update.
    @State private var installState: [String: Bool] = [:]

    /// Stable display order: claude, qoder, qoderwork, cursor.
    private let orderedIds: [String] = ["claude", "qoder", "qoderwork", "cursor"]

    var body: some View {
        Form {
            Section {
                Text("管理 Session Cove 钩入哪些 AI 编程框架。Claude Code 始终启用,其余为实验性接入。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("框架") {
                ForEach(providersInOrder, id: \.id) { provider in
                    providerRow(provider)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label("实验性接入", systemImage: "exclamationmark.triangle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text("Cursor / Qoder / QoderWork 的 hook 行为与 Claude Code 不完全一致,可能不会按预期工作。启用后会写入对应框架的设置文件,关闭时自动清理。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshInstallState() }
        .onChange(of: settings.enabledProviders) { refreshInstallState() }
    }

    // MARK: - Provider rows

    private var providersInOrder: [any AgentProvider] {
        let registry = AgentProviderRegistry.shared
        return orderedIds.compactMap { registry.provider(for: $0) }
    }

    @ViewBuilder
    private func providerRow(_ provider: any AgentProvider) -> some View {
        HStack(alignment: .center, spacing: 10) {
            statusDot(for: provider.id)

            VStack(alignment: .leading, spacing: 2) {
                Text(provider.displayName)
                    .font(.body)
                Text(installState[provider.id] == true ? "已安装钩子" : "未安装钩子")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Manual install / uninstall affordance — useful when the
            // user wants to force a re-install (e.g. after editing the
            // target settings.json by hand) without toggling off-and-on.
            // Buttons go through the same code path the toggle observer
            // uses, so behavior is identical.
            Button(installState[provider.id] == true ? "重装" : "安装") {
                runInstall(providerId: provider.id)
            }
            .controlSize(.small)
            .disabled(!settings.enabledProviders.contains(provider.id))

            Toggle("", isOn: toggleBinding(for: provider.id))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(provider.id == "claude")  // Claude is mandatory.
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func statusDot(for providerId: String) -> some View {
        let installed = installState[providerId] == true
        Circle()
            .fill(installed ? Color.green : Color.secondary.opacity(0.4))
            .frame(width: 8, height: 8)
            .help(installed ? "钩子已安装" : "钩子未安装")
    }

    // MARK: - Bindings & actions

    /// Binding that adds/removes a provider id from the `Set<String>`.
    /// `enabledProviders` posts the change notification on its own
    /// `didSet`, so this binding doesn't need to fan out installs
    /// directly — `WindowManager` does that.
    private func toggleBinding(for providerId: String) -> Binding<Bool> {
        Binding(
            get: { settings.enabledProviders.contains(providerId) },
            set: { newValue in
                var set = settings.enabledProviders
                if newValue {
                    set.insert(providerId)
                } else {
                    set.remove(providerId)
                }
                settings.enabledProviders = set
            }
        )
    }

    private func runInstall(providerId: String) {
        switch providerId {
        case "claude":    try? ClaudePermissionHook.installForClaude()
        case "qoder":     try? ClaudePermissionHook.installForQoder()
        case "qoderwork": try? ClaudePermissionHook.installForQoderWork()
        case "cursor":    try? ClaudePermissionHook.installForCursor()
        default:          break
        }
        refreshInstallState()
    }

    private func refreshInstallState() {
        var next: [String: Bool] = [:]
        for id in orderedIds {
            next[id] = ClaudePermissionHook.isInstalled(providerId: id)
        }
        installState = next
    }
}
