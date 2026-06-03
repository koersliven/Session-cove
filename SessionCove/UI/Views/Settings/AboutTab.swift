import SwiftUI
import AppKit

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 12)

            Image(nsImage: NSApp.applicationIconImage ?? NSImage(named: "NSApplicationIcon") ?? NSImage())
                .resizable()
                .interpolation(.high)
                .frame(width: 64, height: 64)

            VStack(spacing: 4) {
                Text("Session Cove")
                    .font(.title2)
                    .bold()
                Text("v\(versionString)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Inspired by ping-island & Dave the Diver")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 18) {
                Link("GitHub", destination: URL(string: "https://github.com/koersliven/Session-cove")!)
                Link("Issues", destination: URL(string: "https://github.com/koersliven/Session-cove/issues")!)
                Link("Star", destination: URL(string: "https://github.com/koersliven/Session-cove")!)
            }

            Spacer()

            Button("检查更新") { }
                .disabled(true)

            Spacer().frame(height: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }
}
