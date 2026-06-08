import Foundation
import AppKit

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    enum State: Equatable {
        case idle
        case checking
        case available(version: String, dmgURL: URL, releaseNotes: String?)
        case downloading(progress: Double)
        case readyToInstall
        case upToDate
        case error(String)
    }

    @Published var state: State = .idle
    @Published var dismissed = false
    private var timer: Timer?

    private let repoURL = "https://api.github.com/repos/koersliven/Session-cove/releases/latest"

    func start() {
        check()
        timer = Timer.scheduledTimer(withTimeInterval: 4 * 3600, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.check() }
        }
    }

    func check() {
        state = .checking
        dismissed = false
        Task {
            do {
                let result = try await fetchLatestRelease()
                if isNewer(remote: result.version, local: currentVersion) {
                    state = .available(version: result.version, dmgURL: result.dmgURL, releaseNotes: result.notes)
                } else {
                    state = .upToDate
                }
            } catch {
                state = .error(error.localizedDescription)
                print("[UpdateChecker] check failed: \(error.localizedDescription)")
            }
        }
    }

    func dismiss() {
        dismissed = true
    }

    /// Download DMG, mount, replace app, relaunch.
    func downloadAndInstall(dmgURL: URL) {
        state = .downloading(progress: 0)
        Task {
            do {
                let localDMG = try await downloadDMG(from: dmgURL)
                state = .readyToInstall
                try installFromDMG(localDMG)
            } catch {
                state = .error("安装失败: \(error.localizedDescription)")
                print("[UpdateChecker] install failed: \(error)")
            }
        }
    }

    private func downloadDMG(from url: URL) async throws -> URL {
        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        if let token = githubToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (tempURL, response) = try await URLSession.shared.download(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        // Move to a stable temp path
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("SessionCove-update.dmg")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tempURL, to: dest)
        return dest
    }

    private func installFromDMG(_ dmgPath: URL) throws {
        let appName = "Session Cove"
        let appPath = "/Applications/\(appName).app"

        // Write an updater script that runs after we quit
        let script = """
        #!/bin/bash
        # Wait for the app to quit
        while pgrep -f "SessionCove$" > /dev/null 2>&1; do sleep 0.5; done
        # Mount DMG
        MOUNT=$(hdiutil attach "\(dmgPath.path)" -nobrowse -quiet -mountrandom /tmp 2>/dev/null | tail -1 | awk '{print $NF}')
        if [ -z "$MOUNT" ]; then exit 1; fi
        # Replace app
        rm -rf "\(appPath)"
        cp -R "$MOUNT/\(appName).app" "\(appPath)"
        # Remove quarantine
        xattr -dr com.apple.quarantine "\(appPath)" 2>/dev/null
        # Unmount
        hdiutil detach "$MOUNT" -quiet 2>/dev/null
        # Clean up DMG
        rm -f "\(dmgPath.path)"
        # Relaunch
        open "\(appPath)"
        # Self-delete
        rm -f "$0"
        """

        let scriptPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("session-cove-updater.sh")
        try script.write(to: scriptPath, atomically: true, encoding: .utf8)

        // Make executable
        let attrs: [FileAttributeKey: Any] = [.posixPermissions: 0o755]
        try FileManager.default.setAttributes(attrs, ofItemAtPath: scriptPath.path)

        // Launch the script detached
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()

        // Quit ourselves
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: - Private

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Optional GitHub token for higher rate limits (5000/h vs 60/h).
    /// Reads from ~/.session-cove/github-token if it exists.
    private var githubToken: String? {
        let tokenFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".session-cove/github-token")
        guard let content = try? String(contentsOf: tokenFile, encoding: .utf8) else { return nil }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private struct ReleaseInfo {
        let version: String
        let dmgURL: URL
        let notes: String?
    }

    private func fetchLatestRelease() async throws -> ReleaseInfo {
        guard let url = URL(string: repoURL) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("SessionCove/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        if let token = githubToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let body = String(data: data.prefix(200), encoding: .utf8) ?? ""
            print("[UpdateChecker] HTTP \(http.statusCode): \(body)")
            throw URLError(.badServerResponse)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }

        guard let tagName = json["tag_name"] as? String else {
            throw URLError(.cannotParseResponse)
        }
        let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        let notes = json["body"] as? String

        // Find DMG asset
        var dmgURL: URL?
        if let assets = json["assets"] as? [[String: Any]] {
            for asset in assets {
                guard let name = asset["name"] as? String,
                      let downloadURL = asset["browser_download_url"] as? String else { continue }
                if name.hasSuffix(".dmg") {
                    dmgURL = URL(string: downloadURL)
                    break
                }
            }
        }

        // Fallback: open release page if no DMG found
        let finalURL = dmgURL ?? URL(string: "https://github.com/koersliven/Session-cove/releases/latest")!

        return ReleaseInfo(version: version, dmgURL: finalURL, notes: notes)
    }

    private func isNewer(remote: String, local: String) -> Bool {
        let rParts = remote.split(separator: ".").compactMap { Int($0) }
        let lParts = local.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(rParts.count, lParts.count) {
            let r = i < rParts.count ? rParts[i] : 0
            let l = i < lParts.count ? lParts[i] : 0
            if r > l { return true }
            if r < l { return false }
        }
        return false
    }
}
