import Foundation
import Combine

/// Matcher carried by an `AllowlistRule`. Schema is shared with the Python hook
/// bridge (`session_cove_claude_hook.py`) — keep `kind` / `value` exactly aligned
/// with the matcher kinds the python script understands:
/// `binaryPrefix` / `exact` / `pathPrefix` / `toolInProject`.
struct AllowlistMatcher: Equatable, Hashable, Codable {
    var kind: String
    var value: String

    init(kind: String, value: String) {
        self.kind = kind
        self.value = value
    }
}

/// One row in `~/.session-cove/hooks/allowlist.json`. The on-disk JSON schema is
/// pinned to the format the python hook (and existing user data) already uses;
/// any field not understood by the python side is simply ignored, so adding
/// `id` and `createdAt` (Date) on top of the existing keys is backwards-compatible.
struct AllowlistRule: Identifiable, Equatable, Hashable {
    let id: UUID
    var toolName: String
    var projectPath: String
    var scope: String          // "always" | "session"
    var sessionId: String?
    var enabled: Bool
    var matcher: AllowlistMatcher
    var createdAt: Date
    /// Owning agent provider, e.g. "claude" / "qoder" / "cursor". Defaults to
    /// "claude" so v1 on-disk rules (no providerId field) decode unchanged;
    /// `loadFromDisk` re-stamps the field so the file converges to v2 once
    /// the user lands on a build that knows about it.
    var providerId: String

    init(
        id: UUID = UUID(),
        toolName: String,
        projectPath: String,
        scope: String = "always",
        sessionId: String? = nil,
        enabled: Bool = true,
        matcher: AllowlistMatcher,
        createdAt: Date = Date(),
        providerId: String = "claude"
    ) {
        self.id = id
        self.toolName = toolName
        self.projectPath = projectPath
        self.scope = scope
        self.sessionId = sessionId
        self.enabled = enabled
        self.matcher = matcher
        self.createdAt = createdAt
        self.providerId = providerId
    }

    /// Decode a single rule object as stored in `allowlist.json`.
    /// Tolerant of legacy entries lacking `id` / `enabled` / `createdAt`
    /// (those keys were added by Session Cove later — the python hook
    /// neither reads nor writes `id`).
    fileprivate static func from(json: [String: Any]) -> AllowlistRule? {
        guard let toolName = json["toolName"] as? String else { return nil }
        guard let matcherJSON = json["matcher"] as? [String: Any],
              let kind = matcherJSON["kind"] as? String,
              let value = matcherJSON["value"] as? String else { return nil }

        let projectPath = json["projectPath"] as? String ?? ""
        let scope = json["scope"] as? String ?? "always"
        let sessionId = (json["sessionId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let enabled = json["enabled"] as? Bool ?? true

        let createdAt: Date
        if let ts = json["createdAt"] as? TimeInterval {
            createdAt = Date(timeIntervalSince1970: ts)
        } else if let ts = json["createdAt"] as? Double {
            createdAt = Date(timeIntervalSince1970: ts)
        } else {
            createdAt = Date()
        }

        let id: UUID
        if let raw = json["id"] as? String, let parsed = UUID(uuidString: raw) {
            id = parsed
        } else {
            id = UUID()
        }

        // v1 rules omit providerId; default to "claude" — the only provider
        // any prior build wrote rules for. `loadFromDisk` re-saves the file
        // so the field is materialized on the next read.
        let providerId: String
        if let raw = json["providerId"] as? String, !raw.isEmpty {
            providerId = raw
        } else {
            providerId = "claude"
        }

        return AllowlistRule(
            id: id,
            toolName: toolName,
            projectPath: projectPath,
            scope: scope,
            sessionId: sessionId,
            enabled: enabled,
            matcher: AllowlistMatcher(kind: kind, value: value),
            createdAt: createdAt,
            providerId: providerId
        )
    }

    /// Encode to the JSON dictionary shape the python hook expects.
    /// `id` is included for Swift-side stability; python ignores unknown keys.
    fileprivate func toJSON() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id.uuidString,
            "toolName": toolName,
            "projectPath": projectPath,
            "scope": scope,
            "enabled": enabled,
            "matcher": [
                "kind": matcher.kind,
                "value": matcher.value
            ],
            "createdAt": createdAt.timeIntervalSince1970,
            "providerId": providerId
        ]
        if let sessionId, !sessionId.isEmpty {
            dict["sessionId"] = sessionId
        }
        return dict
    }
}

/// Single source of truth for the on-disk allowlist that gates Claude tool calls.
/// Owns the read/write side of `~/.session-cove/hooks/allowlist.json` and watches
/// the file for external edits (Settings UI, manual edits, peer Session Cove
/// instances). Callers that only need a snapshot should read `rules`; callers
/// that mutate must go through `add` / `remove` / `clear` / `setEnabled` so the
/// in-memory state and the file stay in sync.
@MainActor
final class AllowlistStore: ObservableObject {
    static let shared = AllowlistStore()

    @Published private(set) var rules: [AllowlistRule] = []

    /// Number of times the store re-read the JSON from disk (init load + every
    /// monitor-triggered reload). Exposed for tests; never reset.
    private(set) var reloadCount: Int = 0

    let storeURL: URL

    private let debounceQueue: DispatchQueue
    private var fileMonitor: AllowlistFileMonitor?
    private var debounceWorkItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 0.2

    /// Timestamp of the last self-write so monitor events triggered by our own
    /// `saveToDisk` don't cause a reload feedback loop.
    private var selfWriteTimestamp: Date?
    private let selfWriteIgnoreWindow: TimeInterval = 0.5

    /// Default URL: `~/.session-cove/hooks/allowlist.json`.
    /// `nonisolated` so it can be evaluated in `init`'s default-argument
    /// position (which runs in a non-isolated context).
    nonisolated static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".session-cove", isDirectory: true)
            .appendingPathComponent("hooks", isDirectory: true)
            .appendingPathComponent("allowlist.json")
    }

    init(
        url: URL = AllowlistStore.defaultURL,
        startMonitoring: Bool = true
    ) {
        self.storeURL = url
        self.debounceQueue = DispatchQueue(label: "AllowlistStore.monitor", qos: .utility)
        ensureDirectoryExists()
        loadFromDisk()
        if startMonitoring {
            startFileMonitor()
        }
    }

    deinit {
        // AllowlistFileMonitor is a plain class with its own deinit-cancel —
        // dropping our reference is enough; no MainActor-isolated work needed.
    }

    // MARK: - Public mutating API

    /// Append `rule` to the store and persist. Idempotent: if a rule with
    /// matching (toolName, matcher, projectPath) already exists, no-op.
    func add(_ rule: AllowlistRule) {
        guard !contains(toolName: rule.toolName, matcher: rule.matcher, projectPath: rule.projectPath) else {
            return
        }
        rules.append(rule)
        saveToDisk()
    }

    /// Remove a specific rule by id. No-op if not found.
    func remove(_ rule: AllowlistRule) {
        let originalCount = rules.count
        rules.removeAll { $0.id == rule.id }
        if rules.count != originalCount {
            saveToDisk()
        }
    }

    /// Drop every rule and persist an empty list.
    func clear() {
        guard !rules.isEmpty else { return }
        rules.removeAll()
        saveToDisk()
    }

    /// Toggle the `enabled` flag on a stored rule (matched by id) and persist.
    /// No-op if the rule is no longer in the store.
    func setEnabled(_ rule: AllowlistRule, _ enabled: Bool) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        guard rules[index].enabled != enabled else { return }
        rules[index].enabled = enabled
        saveToDisk()
    }

    /// Duplicate-detection helper used before adding new rules. `projectPath`
    /// is optional: pass `nil` to test for any rule with the given
    /// (toolName, matcher), or a concrete path to scope the check.
    func contains(toolName: String, matcher: AllowlistMatcher, projectPath: String? = nil) -> Bool {
        rules.contains { rule in
            guard rule.toolName == toolName, rule.matcher == matcher else { return false }
            if let projectPath {
                return rule.projectPath == projectPath
            }
            return true
        }
    }

    /// Force a synchronous reload from disk. Mostly useful for tests.
    func reload() {
        loadFromDisk()
    }

    // MARK: - File I/O

    private func ensureDirectoryExists() {
        let dir = storeURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func loadFromDisk() {
        reloadCount += 1
        guard FileManager.default.fileExists(atPath: storeURL.path),
              let data = try? Data(contentsOf: storeURL) else {
            rules = []
            return
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawRules = json["rules"] as? [[String: Any]] else {
            // Corrupt or unexpected schema — keep memory state, don't blow away
            // user data. File monitor will pick up later valid writes.
            return
        }
        // v1→v2 auto-migration: if any rule on disk lacks `providerId`, decode
        // with the "claude" default (handled in `from(json:)`) and immediately
        // re-save so the field is materialized. Idempotent — once every rule
        // has the field, this branch never fires again. We don't bump a
        // numeric schemaVersion; the field's presence is the marker.
        let needsMigration = rawRules.contains { ($0["providerId"] as? String).map { $0.isEmpty } ?? true }
        rules = rawRules.compactMap(AllowlistRule.from(json:))
        if needsMigration && !rules.isEmpty {
            saveToDisk()
        }
    }

    private func saveToDisk() {
        ensureDirectoryExists()

        let payload: [String: Any] = ["rules": rules.map { $0.toJSON() }]
        guard let data = try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return }

        let tmpURL = storeURL.appendingPathExtension("tmp")
        do {
            try data.write(to: tmpURL, options: .atomic)
            if FileManager.default.fileExists(atPath: storeURL.path) {
                _ = try FileManager.default.replaceItemAt(storeURL, withItemAt: tmpURL)
            } else {
                try FileManager.default.moveItem(at: tmpURL, to: storeURL)
            }
            selfWriteTimestamp = Date()
            // After a successful replace, the monitor's fd points at the old
            // (now-deleted) inode. Re-arm so future external edits are caught.
            restartFileMonitorIfNeeded()
        } catch {
            try? FileManager.default.removeItem(at: tmpURL)
        }
    }

    // MARK: - File monitoring

    private func startFileMonitor() {
        // Make sure the file exists so the dispatch source has something to attach to.
        if !FileManager.default.fileExists(atPath: storeURL.path) {
            try? Data("{\"rules\":[]}".utf8).write(to: storeURL, options: .atomic)
        }
        fileMonitor = AllowlistFileMonitor(url: storeURL, queue: debounceQueue) { [weak self] in
            DispatchQueue.main.async {
                self?.handleFileChange()
            }
        }
    }

    private func restartFileMonitorIfNeeded() {
        guard fileMonitor != nil else { return }
        fileMonitor = nil
        startFileMonitor()
    }

    private func handleFileChange() {
        // Self-write feedback suppression: ignore events fired in the wake of
        // our own atomic replace (file rename + write within ~0.5s).
        if let last = selfWriteTimestamp,
           Date().timeIntervalSince(last) < selfWriteIgnoreWindow {
            return
        }
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.loadFromDisk()
            }
        }
        debounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }
}

// MARK: - File monitor helper

/// Plain (non-MainActor) wrapper around `DispatchSourceFileSystemObject`.
/// Lives outside `AllowlistStore` so its `deinit` can cancel the source
/// without touching MainActor-isolated state.
private final class AllowlistFileMonitor {
    private let source: DispatchSourceFileSystemObject
    private let fd: Int32

    init?(url: URL, queue: DispatchQueue, onChange: @escaping () -> Void) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: queue
        )
        self.source = source
        self.fd = fd
        source.setEventHandler(handler: onChange)
        source.setCancelHandler { close(fd) }
        source.resume()
    }

    deinit {
        source.cancel()
    }
}
