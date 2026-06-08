import AppKit
import SwiftUI

@MainActor
final class WorkspaceEditorWindowController: NSWindowController {
    static let shared = WorkspaceEditorWindowController()

    private var viewModel: CoveViewModel?

    private convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "New Workspace"
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.hidesOnDeactivate = false
        self.init(window: window)
    }

    func show(viewModel: CoveViewModel, editingId: String? = nil) {
        self.viewModel = viewModel
        let editorView = WorkspaceEditorView(
            viewModel: viewModel,
            editingId: editingId,
            onDismiss: { [weak self] in
                self?.window?.close()
            }
        )
        let hosting = NSHostingController(rootView: editorView)
        window?.contentViewController = hosting
        window?.title = editingId != nil ? "Edit Workspace" : "New Workspace"
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class NewSessionWindowController: NSWindowController {
    static let shared = NewSessionWindowController()

    private convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "New Session"
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.hidesOnDeactivate = false
        self.init(window: window)
    }

    func show(viewModel: CoveViewModel) {
        let view = NewSessionView(
            viewModel: viewModel,
            onDismiss: { [weak self] in
                self?.window?.close()
            }
        )
        let hosting = NSHostingController(rootView: view)
        window?.contentViewController = hosting
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
