import AppKit
import SwiftUI

@MainActor
final class PetWindowController: NSWindowController, NSWindowDelegate, CoveModeWindowController {
    let viewModel: CoveViewModel
    private var globalClickMonitor: Any?
    private var hostingView: PassThroughHostingView<CoveRootView>?
    private let strategy = PetPlacementStrategy()
    private var isClosing = false

    var panel: CovePanel? {
        window as? CovePanel
    }

    init(viewModel: CoveViewModel) {
        self.viewModel = viewModel

        guard let screen = NSScreen.screens.first else {
            super.init(window: CovePanel(contentRect: .zero))
            return
        }

        let initialSize = PetPlacementStrategy.petSize
        let screenFrame = screen.visibleFrame

        // Restore persisted anchor if any; clamp into visible frame so a stale
        // off-screen position (after monitor change / resolution change) snaps back.
        let savedAnchor = CoveSettings.shared.petAnchorPoint
        let restoredAnchor = savedAnchor.map {
            PetAnchorGeometry.clamp($0, petSize: initialSize, into: screenFrame)
        }
        let initialOrigin = restoredAnchor ?? NSPoint(
            x: screenFrame.midX - initialSize.width / 2,
            y: screenFrame.maxY - initialSize.height
        )
        let contentRect = NSRect(origin: initialOrigin, size: initialSize)

        let panel = CovePanel(contentRect: contentRect)
        panel.ignoresMouseEvents = false

        super.init(window: panel)
        panel.delegate = self

        // Seed strategy anchor from restored value so the first .pet update
        // honors it (otherwise it would fall back to top-center).
        strategy.setInitialAnchor(restoredAnchor)

        // Drag-end callback: model -> controller without coupling.
        // PetInteractionView.mouseUp runs on the main thread, so MainActor.assumeIsolated
        // gives us a synchronous, allocation-free hop to MainActor isolation.
        viewModel.onPetDragEnded = { [weak self] in
            MainActor.assumeIsolated {
                self?.savePetAnchor()
            }
        }

        let rootView = CoveRootView(
            viewModel: viewModel,
            onFrameSizeChange: { [weak self] newSize in
                self?.updatePanelFrame(for: newSize)
            }
        )
        let hosting = PassThroughHostingView(rootView: rootView)
        hosting.frame = NSRect(origin: .zero, size: initialSize)
        hosting.layer?.backgroundColor = .clear
        hosting.hitTestRectProvider = { [weak hosting] in
            guard let hosting else { return [] }
            return [hosting.bounds]
        }
        panel.contentView = hosting
        self.hostingView = hosting

        updatePanelFrame(for: viewModel.frameSize)

        setupGlobalClickMonitor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - CoveModeWindowController

    /// Convenience no-arg overload required by `CoveModeWindowController`.
    /// The inherited `NSWindowController.showWindow(_:)` takes a sender; the
    /// protocol shape lets PetWindowController and NotchWindowController
    /// (an NSObject) satisfy the same handle.
    func showWindow() {
        showWindow(nil)
        panel?.orderFrontRegardless()
    }

    func handleDisplayModeWillChange() {
        // Persist current position so a later swap back to .pet restores it.
        savePetAnchor()
    }

    // MARK: - Frame placement

    private func updatePanelFrame(for frameSize: CoveFrameSize) {
        guard let panel = panel,
              let screen = panel.screen ?? NSScreen.screens.first else { return }
        let screenFrame = screen.visibleFrame

        strategy.capturePetAnchorIfLeavingPet(currentFrameSize: frameSize, panelOrigin: panel.frame.origin)

        let result = strategy.nextFrame(
            for: frameSize,
            currentPanelOrigin: panel.frame.origin,
            screenFrame: screenFrame,
            pingHeightOverride: viewModel.pingHeight
        )

        if let direction = result.pingDirection {
            viewModel.pingExpandDirection = direction
        }

        panel.setFrame(result.frame, display: true, animate: false)
        hostingView?.frame = NSRect(origin: .zero, size: result.frame.size)
        panel.contentView?.frame = NSRect(origin: .zero, size: result.frame.size)
    }

    func savePetAnchor() {
        guard let origin = panel?.frame.origin else { return }
        strategy.savePetAnchor(origin)
        CoveSettings.shared.petAnchorPoint = origin
    }

    private func setupGlobalClickMonitor() {
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            if MouseEventReplay.isReplayed(event) { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Expanded modes (harbor/island/session) collapse on
                // outside-click; compact bar follows the same. The ping
                // frame stays intact regardless of kind — approval/question
                // are blockers that need a button press; completion toasts
                // intentionally persist so the user keeps working without
                // the toast vanishing under their cursor. Only 知道了 /
                // 打开会话 or the 30s auto-dismiss clears a completion.
                if self.viewModel.isExpanded || self.viewModel.uiMode == .compact {
                    self.viewModel.closeToPet()
                }
            }
        }
    }

    /// Idempotent teardown. Multiple sources can race to close the controller
    /// (displayMode swap + global escape monitor + system events); the guard
    /// prevents double removeMonitor / orderOut.
    override func close() {
        guard !isClosing else { return }
        isClosing = true
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
        viewModel.onPetDragEnded = nil
        super.close()
    }

    deinit {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
