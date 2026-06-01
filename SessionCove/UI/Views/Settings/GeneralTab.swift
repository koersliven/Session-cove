import SwiftUI

struct GeneralTab: View {
    @EnvironmentObject var settings: CoveSettings
    /// Subscribes the view to the singleton via Swift Observation. `@State`
    /// gives the property a stable storage slot across re-renders; reading
    /// `transitionState.isTransitioning` inside `body` registers the view
    /// for change tracking, so the Picker re-renders when WindowManager
    /// flips the flag.
    @State private var transitionState = ModeTransitionState.shared

    var body: some View {
        Form {
            Section("显示模式") {
                VStack(spacing: 12) {
                    HStack(spacing: 24) {
                        ForEach(CoveSettings.DisplayMode.allCases) { mode in
                            Image(systemName: mode.iconName)
                                .font(.system(size: 28))
                                .frame(maxWidth: .infinity)
                                .foregroundStyle(mode == settings.displayMode ? Color.accentColor : Color.secondary)
                        }
                    }
                    Picker("", selection: $settings.displayMode) {
                        ForEach(CoveSettings.DisplayMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .disabled(transitionState.isTransitioning)
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
