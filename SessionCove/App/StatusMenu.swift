import AppKit
import Foundation

/// Builds the status-menu shared between the menu-bar octopus icon and
/// right-clicking the pet itself. Built fresh on each call so dynamic items
/// (mode-toggle title) reflect current state.
@MainActor
enum StatusMenu {
    static func build(target: AnyObject? = nil) -> NSMenu {
        _ = target
        let menu = NSMenu()
        menu.autoenablesItems = false

        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(MenuActionTarget.openSettings(_:)),
            keyEquivalent: ","
        )
        settings.keyEquivalentModifierMask = [.command]
        settings.target = MenuActionTarget.shared
        menu.addItem(settings)

        menu.addItem(.separator())

        let about = NSMenuItem(
            title: "About Session Cove",
            action: #selector(MenuActionTarget.showAbout(_:)),
            keyEquivalent: ""
        )
        about.target = MenuActionTarget.shared
        menu.addItem(about)

        menu.addItem(.separator())

        let isPet = CoveSettings.shared.displayMode == .pet
        let toggleTitle = isPet ? "切换到 Notch 模式" : "切换到 Pet 模式"
        let toggle = NSMenuItem(
            title: toggleTitle,
            action: #selector(MenuActionTarget.toggleMode(_:)),
            keyEquivalent: ""
        )
        toggle.target = MenuActionTarget.shared
        menu.addItem(toggle)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit Session Cove",
            action: #selector(MenuActionTarget.quit(_:)),
            keyEquivalent: "q"
        )
        quit.keyEquivalentModifierMask = [.command]
        quit.target = MenuActionTarget.shared
        menu.addItem(quit)

        return menu
    }
}

@MainActor
private final class MenuActionTarget: NSObject {
    static let shared = MenuActionTarget()

    @objc func openSettings(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    @objc func showAbout(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc func toggleMode(_ sender: Any?) {
        let current = CoveSettings.shared.displayMode
        CoveSettings.shared.displayMode = (current == .pet) ? .notch : .pet
    }

    @objc func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }
}
