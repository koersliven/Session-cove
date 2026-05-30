import SwiftUI
import AppKit

struct DisplayTab: View {
    @EnvironmentObject var settings: CoveSettings

    var body: some View {
        Form {
            Section("内容字号") {
                Picker("字号", selection: $settings.contentFontSize) {
                    Text("11").tag(11.0)
                    Text("13").tag(13.0)
                    Text("15").tag(15.0)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if screenOptions.count > 1 {
                Section("屏幕") {
                    Picker("显示在哪个屏幕", selection: $settings.preferredScreenID) {
                        Text("自动（鼠标所在屏）").tag(Optional<CGDirectDisplayID>.none)
                        ForEach(screenOptions) { entry in
                            Text(entry.name).tag(Optional<CGDirectDisplayID>.some(entry.id))
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            Section("Notch 模式") {
                Picker("展开方式", selection: $settings.notchTrigger) {
                    ForEach(CoveSettings.NotchTrigger.allCases) { trigger in
                        Text(trigger.displayName).tag(trigger)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Pet 模式") {
                Picker("默认锚点", selection: $settings.petAnchorMode) {
                    ForEach(CoveSettings.PetAnchorMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .formStyle(.grouped)
    }

    private struct ScreenOption: Identifiable {
        let id: CGDirectDisplayID
        let name: String
    }

    private var screenOptions: [ScreenOption] {
        NSScreen.screens.compactMap { screen in
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            guard let raw = (screen.deviceDescription[key] as? NSNumber)?.uint32Value else {
                return nil
            }
            return ScreenOption(id: raw, name: screen.localizedName)
        }
    }
}
