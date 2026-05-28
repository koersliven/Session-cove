import SwiftUI

@main
struct SessionCoveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            Text("Session Cove Settings")
                .frame(width: 300, height: 200)
        }
    }
}
