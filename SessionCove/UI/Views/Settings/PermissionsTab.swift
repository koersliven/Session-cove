import SwiftUI

struct PermissionsTab: View {
    @EnvironmentObject var allowlist: AllowlistStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("已授权的工具调用规则")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 6)

            if allowlist.rules.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(allowlist.rules) { rule in
                        ruleRow(rule)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    allowlist.remove(rule)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            HStack {
                Button("Add Rule…") { }
                    .disabled(true)
                Spacer()
                Button(role: .destructive) {
                    allowlist.clear()
                } label: {
                    Text("Clear All")
                }
                .disabled(allowlist.rules.isEmpty)
            }
            .padding(12)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "尚无规则",
            systemImage: "lock.shield",
            description: Text("授权工具调用后规则会显示在这里")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func ruleRow(_ rule: AllowlistRule) -> some View {
        HStack(spacing: 10) {
            Image(systemName: toolIcon(rule.toolName))
                .frame(width: 22, height: 22)
                .foregroundStyle(rule.enabled ? Color.accentColor : Color.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.toolName)
                    .font(.body)
                    .bold()
                Text(matcherDescription(rule.matcher))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Text(truncate(rule.projectPath))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.head)

            Toggle("", isOn: Binding(
                get: { rule.enabled },
                set: { allowlist.setEnabled(rule, $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .frame(width: 32)
        }
        .padding(.vertical, 4)
    }

    private func toolIcon(_ toolName: String) -> String {
        switch toolName {
        case "Bash": return "terminal"
        case "Edit", "Write", "MultiEdit": return "pencil"
        case "Read": return "doc.text"
        default: return "wrench.and.screwdriver"
        }
    }

    private func matcherDescription(_ matcher: AllowlistMatcher) -> String {
        let kindLabel: String
        switch matcher.kind {
        case "exact": kindLabel = "精确"
        case "binaryPrefix": kindLabel = "命令前缀"
        case "pathPrefix": kindLabel = "路径前缀"
        case "toolInProject": kindLabel = "项目内"
        default: kindLabel = matcher.kind
        }
        return matcher.value.isEmpty ? kindLabel : "\(kindLabel) · \(matcher.value)"
    }

    private func truncate(_ path: String, max: Int = 30) -> String {
        guard path.count > max else { return path }
        return "…" + path.suffix(max - 1)
    }
}
