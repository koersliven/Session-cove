import SwiftUI

struct GeneralTab: View {
    @EnvironmentObject var settings: CoveSettings

    var body: some View {
        Form {
            Section("显示模式") {
                // Custom two-button row — icon + label live in the same
                // view, so the highlight never lags behind. The earlier
                // (icon row) + (segmented Picker) layout had a visible
                // mismatch during mode swap because the segmented control
                // animates separately from the reactive icon row.
                HStack(spacing: 12) {
                    ForEach(CoveSettings.DisplayMode.allCases) { mode in
                        DisplayModeOption(
                            mode: mode,
                            isSelected: mode == settings.displayMode
                        ) {
                            guard settings.displayMode != mode else { return }
                            settings.displayMode = mode
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("启动") {
                Toggle("登录时自动启动", isOn: $settings.launchAtLogin)
            }

            Section("音效") {
                Toggle("启用音效", isOn: $settings.soundEnabled)
                if settings.soundEnabled {
                    HStack {
                        Image(systemName: "speaker.fill")
                            .foregroundStyle(.secondary)
                        Slider(value: $settings.soundVolume, in: 0...1)
                        Image(systemName: "speaker.wave.3.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("通知") {
                Toggle(isOn: $settings.silenceCompletionWhenTerminalFrontmost) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("终端在前台时静默完成提示")
                        Text("当 iTerm / Terminal / Ghostty 等终端正在使用时,Claude 完成回合不再弹窗。关闭后任何场景都弹。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Terminal selection. Bound to `preferredTerminal` (Optional<TerminalKind>);
            // nil = auto-detect (the default), Some(kind) = user-pinned. Non-installed
            // kinds are surfaced with a "(未安装)" suffix rather than hidden, so the
            // user notices when their pinned choice has been uninstalled. Selecting a
            // non-installed kind is harmless because `TerminalDetector.resolvedTerminal()`
            // falls through to ancestor / installed cascade in that case.
            Section("终端") {
                Picker("首选终端", selection: $settings.preferredTerminal) {
                    Text("自动检测").tag(Optional<TerminalKind>.none)
                    ForEach(TerminalKind.allCases, id: \.self) { kind in
                        Text(terminalPickerLabel(for: kind))
                            .tag(Optional<TerminalKind>.some(kind))
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    Text("当前检测")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(detectedTerminalName)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            Section("语言") {
                Picker("界面语言", selection: .constant(0)) {
                    Text("跟随系统").tag(0)
                }
                .disabled(true)
            }
        }
        .formStyle(.grouped)
    }

    /// Picker row label. Appends "(未安装)" when the terminal's bundle is not
    /// registered with Launch Services, matching the same probe used by
    /// `TerminalDetector.installedTerminals()` so the picker stays in sync
    /// with the cascade's reality.
    private func terminalPickerLabel(for kind: TerminalKind) -> String {
        let installed = TerminalAdapterHelpers.isAppInstalled(bundleID: kind.bundleID)
        return installed ? kind.displayName : "\(kind.displayName)（未安装）"
    }

    /// Resolves the terminal that resume operations would actually use right
    /// now. Reads from `TerminalDetector` so any change to `preferredTerminal`
    /// (or installed-app state via NSWorkspace) re-renders this row.
    private var detectedTerminalName: String {
        TerminalDetector.resolvedTerminal().kind.displayName
    }
}

/// Single-tile display-mode selector. Icon + label sit inside the same
/// button, with one source of truth for the highlight state — eliminates
/// the lag the earlier (icon row + segmented Picker) layout exhibited
/// where the icon flipped instantly but the Picker text dragged behind.
private struct DisplayModeOption: View {
    let mode: CoveSettings.DisplayMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: mode.iconName)
                    .font(.system(size: 24))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                Text(mode.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.18), lineWidth: 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
