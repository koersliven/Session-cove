import Foundation

final class DiagnosticLogger: @unchecked Sendable {
    static let shared = DiagnosticLogger()

    private let logDir: URL
    private let logFile: URL
    private let maxSize: UInt64 = 500_000 // 500KB
    private let maxBackups = 2
    private let queue = DispatchQueue(label: "session-cove.logger", qos: .utility)
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private init() {
        logDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".session-cove/logs", isDirectory: true)
        logFile = logDir.appendingPathComponent("app.log")
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
    }

    func log(_ message: String, module: String) {
        let timestamp = dateFormatter.string(from: Date())
        let line = "[\(timestamp)] [\(module)] \(message)\n"
        queue.async { [self] in
            rotateIfNeeded()
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: logFile.path) {
                    if let handle = try? FileHandle(forWritingTo: logFile) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        handle.closeFile()
                    }
                } else {
                    try? data.write(to: logFile)
                }
            }
        }
    }

    func recentLines(count: Int = 300) -> String {
        guard let content = try? String(contentsOf: logFile, encoding: .utf8) else { return "" }
        let lines = content.components(separatedBy: .newlines)
        return lines.suffix(count).joined(separator: "\n")
    }

    private func rotateIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logFile.path),
              let size = attrs[.size] as? UInt64,
              size > maxSize else { return }

        let fm = FileManager.default
        // Shift: app.1.log → app.2.log, app.log → app.1.log
        for i in stride(from: maxBackups - 1, through: 1, by: -1) {
            let src = logDir.appendingPathComponent("app.\(i).log")
            let dst = logDir.appendingPathComponent("app.\(i + 1).log")
            try? fm.removeItem(at: dst)
            try? fm.moveItem(at: src, to: dst)
        }
        let backup1 = logDir.appendingPathComponent("app.1.log")
        try? fm.removeItem(at: backup1)
        try? fm.moveItem(at: logFile, to: backup1)
    }
}
