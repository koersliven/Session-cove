import AppKit
import SwiftUI

@MainActor
final class CoveWindowController: NSWindowController, NSWindowDelegate {
    private let viewModel: CoveViewModel
    private var globalClickMonitor: Any?
    private var hostingView: NSHostingView<CoveRootView>?

    private let compactSize = NSSize(width: 300, height: 50)
    private let expandedSize = NSSize(width: 1040, height: 700)

    var covePanel: CovePanel? {
        window as? CovePanel
    }

    init(viewModel: CoveViewModel) {
        self.viewModel = viewModel

        guard let screen = NSScreen.screens.first else {
            let panel = CovePanel(contentRect: .zero)
            super.init(window: panel)
            return
        }

        let screenFrame = screen.visibleFrame
        let startExpanded = viewModel.isExpanded
        let contentRect: NSRect
        if startExpanded {
            contentRect = NSRect(
                x: screenFrame.midX - expandedSize.width / 2,
                y: screenFrame.maxY - expandedSize.height - 10,
                width: expandedSize.width,
                height: expandedSize.height
            )
        } else {
            contentRect = NSRect(
                x: screenFrame.midX - compactSize.width / 2,
                y: screenFrame.maxY - compactSize.height,
                width: compactSize.width,
                height: compactSize.height
            )
        }

        let panel = CovePanel(contentRect: contentRect)
        panel.ignoresMouseEvents = false

        let rootView = CoveRootView(viewModel: viewModel)
        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = NSRect(origin: .zero, size: contentRect.size)
        panel.contentView = hosting
        self.hostingView = hosting

        super.init(window: panel)
        panel.delegate = self

        setupGlobalClickMonitor()
        observeExpansion()

        DispatchQueue.main.async { [weak self] in
            self?.updatePanelFrame()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func observeExpansion() {
        withObservationTracking {
            _ = viewModel.isExpanded
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.updatePanelFrame()
                self?.observeExpansion()
            }
        }
    }

    private func updatePanelFrame() {
        guard let panel = covePanel, let screen = NSScreen.screens.first else { return }
        let screenFrame = screen.visibleFrame

        if viewModel.isExpanded {
            let newFrame = NSRect(
                x: screenFrame.midX - expandedSize.width / 2,
                y: screenFrame.maxY - expandedSize.height - 10,
                width: expandedSize.width,
                height: expandedSize.height
            )
            panel.setFrame(newFrame, display: true, animate: true)
            panel.makeKey()
        } else {
            let newFrame = NSRect(
                x: screenFrame.midX - compactSize.width / 2,
                y: screenFrame.maxY - compactSize.height,
                width: compactSize.width,
                height: compactSize.height
            )
            panel.setFrame(newFrame, display: true, animate: true)
        }

        hostingView?.frame = NSRect(origin: .zero, size: panel.frame.size)
    }

    private func setupGlobalClickMonitor() {
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.viewModel.isExpanded else { return }
                self.viewModel.toggle()
            }
        }
    }

    deinit {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
