import SwiftUI

@main
struct SessionCoveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsRoot()
                .environmentObject(CoveSettings.shared)
                .environmentObject(AllowlistStore.shared)
        }
    }
}
