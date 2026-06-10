import SwiftUI
import AppKit
import UniformTypeIdentifiers

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

                LabeledContent("尺寸") {
                    HStack(spacing: 8) {
                        Slider(value: $settings.petDisplaySize, in: CoveSettings.petSizeRange, step: 2)
                            .frame(width: 120)
                        Text("\(Int(settings.petDisplaySize))pt")
                            .font(.caption.monospaced())
                            .frame(width: 32, alignment: .trailing)
                    }
                }

                LabeledContent("自定义形象") {
                    HStack(spacing: 10) {
                        customPetPreview
                        Button("上传图片") { pickCustomPetImage() }
                        if settings.customPetImagePath != nil {
                            Button("恢复默认") { clearCustomPetImage() }
                        }
                    }
                }

                Text("上传任意图片作为悬浮宠物。会按图片比例自动适配，不会拉伸变形；透明 PNG 效果最佳。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Custom pet image

    @ViewBuilder
    private var customPetPreview: some View {
        if let path = settings.customPetImagePath,
           let image = MascotImage.loadCustom(path: path) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.secondary.opacity(0.12))
                )
        } else {
            Image(systemName: "pawprint.circle")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
        }
    }

    private func pickCustomPetImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .tiff, .bmp, .heic, .image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "选择"
        panel.message = "选择一张图片作为悬浮宠物形象"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let saved = CustomPetImageStore.save(from: url) {
            settings.customPetImagePath = saved
        }
    }

    private func clearCustomPetImage() {
        settings.customPetImagePath = nil
        CustomPetImageStore.clearFiles()
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
