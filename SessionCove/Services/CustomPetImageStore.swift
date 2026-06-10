import AppKit
import Foundation

/// Persists the user-uploaded Pet-mode mascot image into Session Cove's
/// support directory (`~/.session-cove/`).
///
/// We copy the picked file out of its original location (which may be a
/// temporary or sandbox-scoped URL the app can't read later) into a stable,
/// app-owned path. The filename is timestamped so every upload yields a new
/// path — that lets `CoveSettings.customPetImagePath` change value on each
/// upload, which in turn drives the pet view's reload (a fixed filename would
/// produce an identical path and the view would keep showing the old, cached
/// image).
enum CustomPetImageStore {
    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".session-cove", isDirectory: true)
    }

    /// Copy `source` into the support dir under a fresh timestamped name and
    /// return the destination path. Any previously stored custom-pet file is
    /// removed first so the directory never accumulates orphans. Returns nil
    /// on copy failure (caller leaves the existing selection untouched).
    static func save(from source: URL) -> String? {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        clearFiles()

        let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension
        let dest = directory.appendingPathComponent(
            "custom-pet-\(Int(Date().timeIntervalSince1970)).\(ext)"
        )
        do {
            try fm.copyItem(at: source, to: dest)
            return dest.path
        } catch {
            return nil
        }
    }

    /// Remove every stored custom-pet image. Used by the "恢复默认" button and
    /// before each new upload.
    static func clearFiles() {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }
        for url in items where url.lastPathComponent.hasPrefix("custom-pet-") {
            try? fm.removeItem(at: url)
        }
    }
}
