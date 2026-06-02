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

        if MenuActionTarget.shared.viewModel != nil {
            let mockApproval = NSMenuItem(
                title: "Debug: Mock Approval Request",
                action: #selector(MenuActionTarget.mockApproval(_:)),
                keyEquivalent: ""
            )
            mockApproval.target = MenuActionTarget.shared
            menu.addItem(mockApproval)

            let mockApprovalDetail = NSMenuItem(
                title: "Debug: Mock Approval (with detail)",
                action: #selector(MenuActionTarget.mockApprovalDetail(_:)),
                keyEquivalent: ""
            )
            mockApprovalDetail.target = MenuActionTarget.shared
            menu.addItem(mockApprovalDetail)

            let mockQuestion = NSMenuItem(
                title: "Debug: Mock Question Request",
                action: #selector(MenuActionTarget.mockQuestion(_:)),
                keyEquivalent: ""
            )
            mockQuestion.target = MenuActionTarget.shared
            menu.addItem(mockQuestion)

            let mockCompletion = NSMenuItem(
                title: "Debug: Mock Completion Toast",
                action: #selector(MenuActionTarget.mockCompletion(_:)),
                keyEquivalent: ""
            )
            mockCompletion.target = MenuActionTarget.shared
            menu.addItem(mockCompletion)

            menu.addItem(.separator())
        }

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
final class MenuActionTarget: NSObject {
    static let shared = MenuActionTarget()

    /// Set by WindowManager.setup so debug menu items can drive the live
    /// CoveViewModel without StatusMenu callers needing to thread it through.
    weak var viewModel: CoveViewModel?

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

    @objc func mockApproval(_ sender: Any?) {
        viewModel?.showMockHookRequest()
    }

    @objc func mockApprovalDetail(_ sender: Any?) {
        viewModel?.showMockApprovalWithDetail()
    }

    @objc func mockQuestion(_ sender: Any?) {
        viewModel?.showMockQuestionRequest()
    }

    @objc func mockCompletion(_ sender: Any?) {
        viewModel?.showMockCompletionRequest()
    }

    @objc func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }
}
