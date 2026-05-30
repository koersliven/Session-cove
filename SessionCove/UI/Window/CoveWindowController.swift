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
    private var petAnchor: NSPoint?

    var covePanel: CovePanel? {
        window as? CovePanel
    }

    init(viewModel: CoveViewModel) {
        self.viewModel = viewModel

        guard let screen = NSScreen.screens.first else {
            super.init(window: CovePanel(contentRect: .zero))
            return
        }

        let initialSize = Self.petSize
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

    private static let petSize = NSSize(width: 48, height: 48)
    private static let pingCardWidth: CGFloat = 340
    private static let pingHeight: CGFloat = 72

    private func size(for frameSize: CoveFrameSize) -> NSSize {
        switch frameSize {
        case .pet:     Self.petSize
        case .compact: NSSize(width: 300, height: 50)
        case .ping:    NSSize(width: Self.petSize.width + Self.pingCardWidth, height: Self.pingHeight)
        case .expanded: NSSize(width: 520, height: 480)
        }
    }

    private var previousFrameSize: CoveFrameSize = .pet

    private func updatePanelFrame(for frameSize: CoveFrameSize) {
        guard let panel = covePanel,
              let screen = panel.screen ?? NSScreen.screens.first else { return }
        let screenFrame = screen.visibleFrame

        if previousFrameSize == .pet && frameSize != .pet {
            petAnchor = panel.frame.origin
        }
        previousFrameSize = frameSize

        let newSize = size(for: frameSize)
        let newFrame: NSRect

        switch frameSize {
        case .pet:
            let origin = petAnchor ?? NSPoint(
                x: screenFrame.midX - newSize.width / 2,
                y: screenFrame.maxY - newSize.height
            )
            newFrame = NSRect(origin: origin, size: newSize)

        case .ping:
            let anchor = petAnchor ?? panel.frame.origin
            let petCenterX = anchor.x + Self.petSize.width / 2
            let expandRight = petCenterX < screenFrame.midX
            viewModel.pingExpandDirection = expandRight ? .trailing : .leading

            let originX: CGFloat
            if expandRight {
                originX = anchor.x
            } else {
                originX = anchor.x + Self.petSize.width - newSize.width
            }
            let originY = anchor.y + Self.petSize.height / 2 - newSize.height / 2
            newFrame = clampToScreen(
                NSRect(x: originX, y: originY, width: newSize.width, height: newSize.height),
                screen: screenFrame
            )

        case .expanded:
            let anchor = petAnchor ?? NSPoint(
                x: screenFrame.midX - Self.petSize.width / 2,
                y: screenFrame.maxY - Self.petSize.height
            )
            let petCenterX = anchor.x + Self.petSize.width / 2
            let petCenterY = anchor.y + Self.petSize.height / 2
            let originX = petCenterX - newSize.width / 2
            let originY = petCenterY - newSize.height + 48
            newFrame = clampToScreen(
                NSRect(x: originX, y: originY, width: newSize.width, height: newSize.height),
                screen: screenFrame
            )

        case .compact:
            let anchor = petAnchor ?? NSPoint(
                x: screenFrame.midX - Self.petSize.width / 2,
                y: screenFrame.maxY - Self.petSize.height
            )
            let petCenterX = anchor.x + Self.petSize.width / 2
            let originX = petCenterX - newSize.width / 2
            let originY = anchor.y + Self.petSize.height / 2 - newSize.height / 2
            newFrame = clampToScreen(
                NSRect(x: originX, y: originY, width: newSize.width, height: newSize.height),
                screen: screenFrame
            )
        }

        panel.setFrame(newFrame, display: true, animate: false)
        hostingView?.frame = NSRect(origin: .zero, size: newSize)
        panel.contentView?.frame = NSRect(origin: .zero, size: newSize)
    }

    private func clampToScreen(_ rect: NSRect, screen: NSRect) -> NSRect {
        var r = rect
        if r.maxX > screen.maxX { r.origin.x = screen.maxX - r.width }
        if r.minX < screen.minX { r.origin.x = screen.minX }
        if r.maxY > screen.maxY { r.origin.y = screen.maxY - r.height }
        if r.minY < screen.minY { r.origin.y = screen.minY }
        return r
    }

    func savePetAnchor() {
        petAnchor = covePanel?.frame.origin
    }

    private func setupGlobalClickMonitor() {
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.viewModel.isExpanded || self.viewModel.uiMode == .compact {
                    self.viewModel.closeToPet()
                }
            }
        }
    }

    deinit {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
