import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowManager: WindowManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        windowManager = WindowManager()
        windowManager?.setup()
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowManager?.teardown()
    }
}
