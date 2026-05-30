import AppKit
import SwiftUI

@MainActor
final class WindowManager {
    private var controller: CoveModeWindowController?
    private var viewModel: CoveViewModel?
    private var displayModeObserver: NSObjectProtocol?

    func setup() {
        let viewModel = CoveViewModel()
        self.viewModel = viewModel

        do {
            try ClaudePermissionHook.install()
            viewModel.startHookPolling()
        } catch {
            viewModel.hookIntegrationError = error.localizedDescription
        }

        installController(for: CoveSettings.shared.displayMode, viewModel: viewModel)

        // Defer the swap one runloop tick so SwiftUI Picker can finish committing
        // its binding before we tear down/rebuild the controller (avoids a
        // commit-vs-deinit race that freezes the UI). The inner `[weak self]`
        // recapture is required: NotificationCenter's @Sendable closure gives
        // us a captured weak var that cannot cross into another Sendable closure.
        displayModeObserver = NotificationCenter.default.addObserver(
            forName: .coveDisplayModeDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    self?.swapForCurrentMode()
                }
            }
        }

        Task { await viewModel.initialScan() }
    }

    func teardown() {
        if let observer = displayModeObserver {
            NotificationCenter.default.removeObserver(observer)
            displayModeObserver = nil
        }
        viewModel?.stopHookPolling()
        controller?.handleDisplayModeWillChange()
        controller?.close()
        controller = nil
        viewModel = nil
    }

    private func installController(for mode: CoveSettings.DisplayMode, viewModel: CoveViewModel) {
        let new: CoveModeWindowController
        switch mode {
        case .pet:   new = PetWindowController(viewModel: viewModel)
        case .notch: new = NotchWindowController(viewModel: viewModel)
        }
        new.showWindow()
        controller = new
    }

    private func swapForCurrentMode() {
        guard let viewModel else { return }
        controller?.handleDisplayModeWillChange()
        controller?.close()
        installController(for: CoveSettings.shared.displayMode, viewModel: viewModel)
    }
}
