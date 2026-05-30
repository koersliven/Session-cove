import AppKit
import SwiftUI

@MainActor
final class NotchWindowController: NSObject, CoveModeWindowController {
    let viewModel: CoveViewModel
    private(set) var panel: CovePanel?
    private var hostingView: PassThroughHostingView<CoveNotchView>?
    private var screenObserverToken: UUID?

    init(viewModel: CoveViewModel) {
        self.viewModel = viewModel
        super.init()

        guard let screen = NSScreen.builtin ?? NSScreen.main else { return }

        let panelFrame = NotchPlacementStrategy.panelFrame(for: screen)
        let p = CovePanel(contentRect: panelFrame)
        // PR 3 closed state: full passthrough so the menu bar (clock, WiFi, …)
        // remains clickable behind the notch panel.
        p.ignoresMouseEvents = true
        self.panel = p

        let hosting = PassThroughHostingView(rootView: CoveNotchView(viewModel: viewModel))
        hosting.frame = NSRect(origin: .zero, size: panelFrame.size)
        hosting.layer?.backgroundColor = .clear
        hosting.hitTestRectProvider = { [] }
        p.contentView = hosting
        self.hostingView = hosting

        screenObserverToken = ScreenObserver.shared.subscribe { [weak self] in
            self?.repositionForScreenChange()
        }
    }

    func showWindow() {
        panel?.orderFrontRegardless()
    }

    func close() {
        panel?.orderOut(nil)
    }

    func handleDisplayModeWillChange() {
        if let token = screenObserverToken {
            ScreenObserver.shared.unsubscribe(token)
            screenObserverToken = nil
        }
        close()
    }

    private func repositionForScreenChange() {
        guard let screen = NSScreen.builtin ?? NSScreen.main, let panel else { return }
        panel.setFrame(NotchPlacementStrategy.panelFrame(for: screen), display: true, animate: false)
        hostingView?.frame = NSRect(origin: .zero, size: panel.frame.size)
    }

    deinit {
        // ScreenObserver is @MainActor; deinit can run on any queue but AppKit
        // controllers are torn down on the main thread, so assumeIsolated is
        // a synchronous bridge with no extra hop.
        if let token = screenObserverToken {
            MainActor.assumeIsolated {
                ScreenObserver.shared.unsubscribe(token)
            }
        }
    }
}
