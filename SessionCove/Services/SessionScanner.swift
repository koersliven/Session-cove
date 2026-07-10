import Foundation

enum SessionScanner {
    /// Backward-compatible entry point. Scans the union of all currently
    /// enabled providers (today: just Claude). Existing call sites can keep
    /// invoking `SessionScanner.scan()` and observe identical behavior.
    @MainActor
    static func scan() -> [ProjectIsland] {
        scan(providers: AgentProviderRegistry.shared.enabled())
    }

    /// Multi-provider scan. Each provider's `transcriptRoot` is walked
    /// independently; resulting `ProjectIsland`s are tagged with the
    /// provider's id. Roots that don't exist on disk are skipped with a
    /// log line — never a crash.
    static func scan(providers: [any AgentProvider]) -> [ProjectIsland] {
        var islands: [ProjectIsland] = []

        for provider in providers {
            islands.append(contentsOf: scan(provider: provider))
        }

        islands.sort {
            ($0.sessions.first?.lastModified ?? .distantPast)
                > ($1.sessions.first?.lastModified ?? .distantPast)
        }
        return islands
    }

    // MARK: - Per-provider scan

    private static func scan(provider: any AgentProvider) -> [ProjectIsland] {
        switch provider.transcriptLayout {
        case .projectDirectories:
            return scanProjectDirectories(provider: provider)
        case .flatDatePartitioned:
            return scanFlatDatePartitioned(provider: provider)
        }
    }

    /// Claude / Qoder / Cursor layout: `<root>/<encodedProject>/<subpath>/*.jsonl`.
    private static func scanProjectDirectories(provider: any AgentProvider) -> [ProjectIsland] {
        let fileManager = FileManager.default
        let root = provider.transcriptRoot
        let rootPath = root.path

        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: rootPath, isDirectory: &isDir), isDir.boolValue else {
            print("[SessionScanner] transcriptRoot missing for provider \(provider.id): \(rootPath)")
            return []
        }

        guard let projectDirs = try? fileManager.contentsOfDirectory(atPath: rootPath) else {
            return []
        }

        var islands: [ProjectIsland] = []

        for dirName in projectDirs {
            let dirPath = "\(rootPath)/\(dirName)"
            var isProjectDir: ObjCBool = false
            guard fileManager.fileExists(atPath: dirPath, isDirectory: &isProjectDir),
                  isProjectDir.boolValue else {
                continue
            }

            // Walk every configured subpath so providers like Qoder, whose
            // transcripts live both at the project root AND under a
            // `transcript/` subdirectory, get full coverage. Most providers
            // declare `[""]` (Claude default) and only walk the project root.
            var jsonlPaths: [(filePath: String, fileName: String)] = []
            for subpath in provider.transcriptSubpaths {
                let scanPath = subpath.isEmpty ? dirPath : "\(dirPath)/\(subpath)"
                var isSubDir: ObjCBool = false
                guard fileManager.fileExists(atPath: scanPath, isDirectory: &isSubDir),
                      isSubDir.boolValue else {
                    continue
                }
                guard let files = try? fileManager.contentsOfDirectory(atPath: scanPath) else {
                    continue
                }
                for file in files where file.hasSuffix(".jsonl") && !file.hasPrefix("agent-") {
                    jsonlPaths.append((filePath: "\(scanPath)/\(file)", fileName: file))
                }
            }
            guard !jsonlPaths.isEmpty else { continue }

            var sessions: [SessionRecord] = []
            for entry in jsonlPaths {
                if let record = SessionParser.parse(
                    filePath: entry.filePath,
                    projectDirEncoded: dirName,
                    providerId: provider.id
                ) {
                    sessions.append(record)
                }
            }

            guard !sessions.isEmpty else { continue }

            sessions.sort { $0.lastModified > $1.lastModified }

            let displayName = sessions.first?.projectPath
                .components(separatedBy: "/").last ?? dirName

            // Namespace island ids by provider so two providers with the same
            // encoded project dir don't collide in `islands` keyed lookups.
            let islandId = provider.id == "claude" ? dirName : "\(provider.id):\(dirName)"

            let island = ProjectIsland(
                id: islandId,
                providerId: provider.id,
                path: sessions.first?.projectPath ?? dirName,
                displayName: displayName,
                sessions: sessions
            )
            islands.append(island)
        }

        return islands
    }

    // MARK: - Flat, date-partitioned scan (Codex)

    /// Codex layout: `<root>/YYYY/MM/DD/rollout-<ts>-<uuid>.jsonl`. There is
    /// no per-project directory, so we recursively collect every `.jsonl`,
    /// parse each into a `SessionRecord` (whose `projectPath` comes from the
    /// file's `session_meta.cwd`), then group by `projectPath` into islands.
    private static func scanFlatDatePartitioned(provider: any AgentProvider) -> [ProjectIsland] {
        let fileManager = FileManager.default
        let root = provider.transcriptRoot
        let rootPath = root.path

        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: rootPath, isDirectory: &isDir), isDir.boolValue else {
            print("[SessionScanner] transcriptRoot missing for provider \(provider.id): \(rootPath)")
            return []
        }

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var records: [SessionRecord] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl" else { continue }
            let fileName = fileURL.lastPathComponent
            guard !fileName.hasPrefix("agent-") else { continue }

            // The "encoded dir" for the flat layout is the date-partition path
            // relative to root (e.g. "2026/07/08"), used only as a fallback if
            // the file has no parseable cwd.
            let relativeDir = fileURL.deletingLastPathComponent().path
                .replacingOccurrences(of: rootPath + "/", with: "")

            if let record = SessionParser.parse(
                filePath: fileURL.path,
                projectDirEncoded: relativeDir,
                providerId: provider.id
            ) {
                records.append(record)
            }
        }

        guard !records.isEmpty else { return [] }

        // Group by resolved project path so all Codex sessions in the same
        // repo collapse into one island (matching Claude's per-project model).
        var grouped: [String: [SessionRecord]] = [:]
        for record in records {
            grouped[record.projectPath, default: []].append(record)
        }

        var islands: [ProjectIsland] = []
        for (projectPath, group) in grouped {
            var sessions = group
            sessions.sort { $0.lastModified > $1.lastModified }

            let displayName = projectPath
                .components(separatedBy: "/").last ?? projectPath
            // Namespace by provider + project path so Codex islands never
            // collide with Claude/Qoder islands keyed on encoded dir names.
            let islandId = "\(provider.id):\(projectPath)"

            let island = ProjectIsland(
                id: islandId,
                providerId: provider.id,
                path: projectPath,
                displayName: displayName,
                sessions: sessions
            )
            islands.append(island)
        }

        return islands
    }
}
