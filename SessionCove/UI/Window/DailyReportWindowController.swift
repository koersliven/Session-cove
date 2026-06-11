import AppKit
import SwiftUI

@MainActor
final class DailyReportWindowController: NSWindowController {
    static let shared = DailyReportWindowController()

    private var viewModel: CoveViewModel?

    private convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "潮汐日报"
        window.center()
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 4)
        window.hidesOnDeactivate = false
        window.minSize = NSSize(width: 480, height: 400)
        self.init(window: window)
    }

    func show(viewModel: CoveViewModel) {
        self.viewModel = viewModel
        viewModel.hasUnreadReport = false
        let reportView = DailyReportView(viewModel: viewModel)
        let hosting = NSHostingController(rootView: reportView)
        window?.contentViewController = hosting
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
