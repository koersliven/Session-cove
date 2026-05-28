import AppKit
import SwiftUI

/// A hosting view that only accepts clicks within configurable hit rects.
/// Points outside those rects pass through to views/windows behind.
final class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    var hitTestRectProvider: (() -> [NSRect])?

    override func hitTest(_ point: NSPoint) -> NSView? {
        let rects = hitTestRectProvider?() ?? [bounds]
        guard rects.contains(where: { $0.contains(point) }) else {
            return nil
        }
        return super.hitTest(point)
    }

    /// Accept first mouse click without requiring prior activation.
    /// Critical for non-activating panels where buttons must respond immediately.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

@MainActor
final class CoveWindowController: NSWindowController, NSWindowDelegate {
    private let viewModel: CoveViewModel
    private var globalClickMonitor: Any?
    private var hostingView: PassThroughHostingView<CoveRootView>?

    var covePanel: CovePanel? {
        window as? CovePanel
    }

    init(viewModel: CoveViewModel) {
        self.viewModel = viewModel

        guard let screen = NSScreen.screens.first else {
            super.init(window: CovePanel(contentRect: .zero))
            return
        }

        let initialSize = Self.size(for: .compact)
        let screenFrame = screen.visibleFrame
        let contentRect = NSRect(
            x: screenFrame.midX - initialSize.width / 2,
            y: screenFrame.maxY - initialSize.height,
            width: initialSize.width,
            height: initialSize.height
        )

        let panel = CovePanel(contentRect: contentRect)
        panel.ignoresMouseEvents = false

        super.init(window: panel)
        panel.delegate = self

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

    private static func size(for frameSize: CoveFrameSize) -> NSSize {
        switch frameSize {
        case .compact: NSSize(width: 300, height: 50)
        case .ping:    NSSize(width: 360, height: 230)
        case .expanded: NSSize(width: 520, height: 480)
        }
    }

    private func updatePanelFrame(for frameSize: CoveFrameSize) {
        guard let panel = covePanel,
              let screen = panel.screen ?? NSScreen.screens.first else { return }
        let screenFrame = screen.visibleFrame
        let newSize = Self.size(for: frameSize)
        let newFrame = NSRect(
            x: screenFrame.midX - newSize.width / 2,
            y: screenFrame.maxY - newSize.height,
            width: newSize.width,
            height: newSize.height
        )
        panel.setFrame(newFrame, display: true, animate: false)
        hostingView?.frame = NSRect(origin: .zero, size: newSize)
        panel.contentView?.frame = NSRect(origin: .zero, size: newSize)
        print("[CoveWindow] frameSize=\(frameSize) target=\(newFrame.size) actual=\(panel.frame.size) hosting=\(hostingView?.frame.size ?? .zero)")
    }

    private func setupGlobalClickMonitor() {
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.viewModel.isExpanded else { return }
                self.viewModel.closeToCompact()
            }
        }
    }

    deinit {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
