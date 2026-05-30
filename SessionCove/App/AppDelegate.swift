import AppKit
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowManager: WindowManager?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        windowManager = WindowManager()
        windowManager?.setup()

        setupStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowManager?.teardown()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let baseImage = MascotImage.idle {
                let icon = NSImage(size: NSSize(width: 18, height: 18))
                icon.lockFocus()
                baseImage.draw(in: NSRect(origin: .zero, size: icon.size))
                icon.unlockFocus()
                button.image = icon
            } else {
                button.title = "🐙"
            }
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let menu = StatusMenu.build(target: nil)
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        DispatchQueue.main.async { [weak self] in self?.statusItem?.menu = nil }
    }
}
