import SwiftUI

@main
struct SessionCoveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // When stdout is a pipe (e.g. swift run > /tmp/log), it's fully
        // buffered — print() output never reaches the file until the buffer
        // fills (~4KB) or the process exits. Force unbuffered so debug logs
        // are usable while the app is alive.
        setbuf(stdout, nil)
    }

    var body: some Scene {
        Settings {
            SettingsRoot()
                .environmentObject(CoveSettings.shared)
                .environmentObject(AllowlistStore.shared)
        }
    }
}
