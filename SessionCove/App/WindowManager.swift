import AppKit
import SwiftUI

@MainActor
final class WindowManager {
    private var panel: CovePanel?
    private var controller: CoveWindowController?
    private var viewModel: CoveViewModel?

    func setup() {
        let viewModel = CoveViewModel()
        self.viewModel = viewModel

        do {
            try ClaudePermissionHook.install()
            viewModel.startHookPolling()
        } catch {
            viewModel.hookIntegrationError = error.localizedDescription
        }

        let controller = CoveWindowController(viewModel: viewModel)
        controller.showWindow(nil)

        controller.covePanel?.orderFrontRegardless()

        self.controller = controller
        self.panel = controller.covePanel

        Task {
            await viewModel.initialScan()
        }
    }

    func teardown() {
        viewModel?.stopHookPolling()
        controller?.close()
        panel = nil
        controller = nil
        viewModel = nil
    }
}
