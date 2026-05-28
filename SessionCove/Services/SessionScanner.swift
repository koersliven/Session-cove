import Foundation

enum SessionScanner {
    private static let projectsPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.claude/projects"
    }()

    static func scan() -> [ProjectIsland] {
        let fileManager = FileManager.default

        guard let projectDirs = try? fileManager.contentsOfDirectory(atPath: projectsPath) else {
            return []
        }

        var islands: [ProjectIsland] = []

        for dirName in projectDirs {
            let dirPath = "\(projectsPath)/\(dirName)"
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: dirPath, isDirectory: &isDir), isDir.boolValue else {
                continue
            }

            guard let files = try? fileManager.contentsOfDirectory(atPath: dirPath) else {
                continue
            }

            let jsonlFiles = files.filter { $0.hasSuffix(".jsonl") && !$0.hasPrefix("agent-") }
            guard !jsonlFiles.isEmpty else { continue }

            var sessions: [SessionRecord] = []

            for file in jsonlFiles {
                let filePath = "\(dirPath)/\(file)"
                if let record = SessionParser.parse(
                    filePath: filePath,
                    projectDirEncoded: dirName
                ) {
                    sessions.append(record)
                }
            }

            guard !sessions.isEmpty else { continue }

            sessions.sort { $0.lastModified > $1.lastModified }

            let displayName = sessions.first?.projectPath
                .components(separatedBy: "/").last ?? dirName

            let island = ProjectIsland(
                id: dirName,
                path: sessions.first?.projectPath ?? dirName,
                displayName: displayName,
                sessions: sessions
            )
            islands.append(island)
        }

        islands.sort { $0.sessions.first?.lastModified ?? .distantPast > $1.sessions.first?.lastModified ?? .distantPast }
        return islands
    }
}
