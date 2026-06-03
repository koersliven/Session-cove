import AppKit
import SwiftUI

/// Hand-rolled Settings window for Session Cove.
///
/// SwiftUI's `Settings { }` scene relies on the standard
/// `showSettingsWindow:` selector reaching the SwiftUI scene management,
/// which works for regular `.regular`-policy apps via the Apple menu's
/// Settings… item. Session Cove runs as `.accessory` (LSUIElement=true,
/// no dock icon, no main menu), so that selector dispatches into nothing
/// and the menu-bar Settings… click silently no-ops.
///
/// We sidestep that by owning the NSWindow ourselves and pushing the
/// existing `SettingsRoot` SwiftUI view into a hosting controller. The
/// status-bar / pet menus call `SettingsWindowController.shared.show()`
/// directly — no selector dispatch, no SwiftUI scene plumbing.
@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Session Cove 设置"
        window.center()
        // Don't release on close — we re-show the same window on subsequent
        // openSettings invocations rather than rebuilding hosting state.
        window.isReleasedWhenClosed = false
        // CovePanel runs at `.mainMenu + 3` (statusBar level) and the notch
        // panel is fullWidth × 750 — it would otherwise occlude the centred
        // settings window. .floating sits above .normal but below the panel
        // so the user can interact with both. Without this the picker
        // appeared unresponsive after a swap because the settings window
        // had effectively been buried.
        window.level = .floating
        // SwiftUI re-renders pause when its hosting window is fully
        // occluded; without this the picker keeps a stale `disabled`
        // state until the user re-presents the window. Hiding-on-deactivate
        // disabled by default, but be explicit so the binding stays live.
        window.hidesOnDeactivate = false

        let root = SettingsRoot()
            .environmentObject(CoveSettings.shared)
            .environmentObject(AllowlistStore.shared)
        let hosting = NSHostingController(rootView: root)
        window.contentViewController = hosting

        self.init(window: window)
    }

    /// Idempotent. Brings the window to front and activates the app so the
    /// user can interact with the settings even when SessionCove is hidden
    /// behind another fullscreen-ish app.
    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
