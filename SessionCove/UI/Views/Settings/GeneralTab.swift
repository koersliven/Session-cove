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

            Section("语言") {
                Picker("界面语言", selection: .constant(0)) {
                    Text("跟随系统").tag(0)
                }
                .disabled(true)
            }
        }
        .formStyle(.grouped)
    }
}
