import XCTest
@testable import SessionCove

@MainActor
final class AllowlistStoreTests: XCTestCase {
    private var tmpDir: URL!
    private var allowlistURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AllowlistStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        allowlistURL = tmpDir.appendingPathComponent("allowlist.json")
    }

    override func tearDown() async throws {
        if let tmpDir, FileManager.default.fileExists(atPath: tmpDir.path) {
            try? FileManager.default.removeItem(at: tmpDir)
        }
        tmpDir = nil
        allowlistURL = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeStore(startMonitoring: Bool = false) -> AllowlistStore {
        AllowlistStore(url: allowlistURL, startMonitoring: startMonitoring)
    }

    private func makeRule(
        toolName: String = "Bash",
        kind: String = "binaryPrefix",
        value: String = "ls",
        projectPath: String = "/Users/test/project",
        enabled: Bool = true
    ) -> AllowlistRule {
        AllowlistRule(
            toolName: toolName,
            projectPath: projectPath,
            scope: "always",
            enabled: enabled,
            matcher: AllowlistMatcher(kind: kind, value: value)
        )
    }

    private func writeRulesDirectly(_ rawRules: [[String: Any]]) throws {
        let payload: [String: Any] = ["rules": rawRules]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: allowlistURL, options: .atomic)
    }

    private func readRawRules() throws -> [[String: Any]] {
        let data = try Data(contentsOf: allowlistURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (json?["rules"] as? [[String: Any]]) ?? []
    }

    // MARK: - Tests

    func testAddPersists() throws {
        let store = makeStore()
        let rule = makeRule(value: "git")

        store.add(rule)

        XCTAssertEqual(store.rules.count, 1)
        XCTAssertEqual(store.rules.first?.matcher.value, "git")

        let raw = try readRawRules()
        XCTAssertEqual(raw.count, 1)
        XCTAssertEqual(raw.first?["toolName"] as? String, "Bash")
        let matcher = raw.first?["matcher"] as? [String: Any]
        XCTAssertEqual(matcher?["kind"] as? String, "binaryPrefix")
        XCTAssertEqual(matcher?["value"] as? String, "git")
        // id and createdAt round-trip into the on-disk JSON
        XCTAssertNotNil(raw.first?["id"] as? String)
        XCTAssertNotNil(raw.first?["createdAt"] as? Double)
    }

    func testRemoveRule() throws {
        let store = makeStore()
        let r1 = makeRule(value: "ls")
        let r2 = makeRule(value: "git")
        store.add(r1)
        store.add(r2)

        guard let stored = store.rules.first(where: { $0.matcher.value == "ls" }) else {
            XCTFail("missing rule")
            return
        }
        store.remove(stored)

        XCTAssertEqual(store.rules.count, 1)
        XCTAssertEqual(store.rules.first?.matcher.value, "git")

        let raw = try readRawRules()
        XCTAssertEqual(raw.count, 1)
    }

    func testClear() throws {
        let store = makeStore()
        store.add(makeRule(value: "ls"))
        store.add(makeRule(value: "git"))
        XCTAssertEqual(store.rules.count, 2)

        store.clear()

        XCTAssertTrue(store.rules.isEmpty)
        let raw = try readRawRules()
        XCTAssertTrue(raw.isEmpty)
    }

    func testContains() {
        let store = makeStore()
        let rule = makeRule(value: "ls", projectPath: "/Users/test/project")
        store.add(rule)

        XCTAssertTrue(store.contains(
            toolName: "Bash",
            matcher: AllowlistMatcher(kind: "binaryPrefix", value: "ls"),
            projectPath: "/Users/test/project"
        ))
        // Different projectPath -> not contained
        XCTAssertFalse(store.contains(
            toolName: "Bash",
            matcher: AllowlistMatcher(kind: "binaryPrefix", value: "ls"),
            projectPath: "/Users/test/other"
        ))
        // Without projectPath -> matches any
        XCTAssertTrue(store.contains(
            toolName: "Bash",
            matcher: AllowlistMatcher(kind: "binaryPrefix", value: "ls")
        ))
        // Different matcher -> not contained
        XCTAssertFalse(store.contains(
            toolName: "Bash",
            matcher: AllowlistMatcher(kind: "binaryPrefix", value: "git")
        ))

        // Idempotent add
        store.add(rule)
        XCTAssertEqual(store.rules.count, 1)
    }

    func testSetEnabled() throws {
        let store = makeStore()
        let rule = makeRule(value: "ls")
        store.add(rule)
        guard let stored = store.rules.first else {
            XCTFail("missing rule")
            return
        }
        XCTAssertTrue(stored.enabled)

        store.setEnabled(stored, false)
        XCTAssertEqual(store.rules.first?.enabled, false)

        let raw = try readRawRules()
        XCTAssertEqual(raw.first?["enabled"] as? Bool, false)
    }

    func testLegacyEntriesGetDefaults() throws {
        // Simulate an existing user file lacking id / enabled / createdAt
        try writeRulesDirectly([
            [
                "toolName": "Bash",
                "projectPath": "/Users/test/project",
                "scope": "always",
                "matcher": ["kind": "binaryPrefix", "value": "ls"]
            ]
        ])

        let store = makeStore()
        XCTAssertEqual(store.rules.count, 1)
        XCTAssertEqual(store.rules.first?.toolName, "Bash")
        XCTAssertEqual(store.rules.first?.enabled, true, "missing enabled key should default to true")
        XCTAssertNotNil(store.rules.first?.id, "missing id should be generated")
    }

    func testAtomicWrite() throws {
        // Pre-existing valid file
        try writeRulesDirectly([
            [
                "id": UUID().uuidString,
                "toolName": "Bash",
                "projectPath": "/x",
                "scope": "always",
                "enabled": true,
                "matcher": ["kind": "binaryPrefix", "value": "ls"],
                "createdAt": Date().timeIntervalSince1970
            ]
        ])

        let store = makeStore()
        XCTAssertEqual(store.rules.count, 1)

        store.add(makeRule(value: "git"))

        // No leftover .tmp file from atomic-replace path
        let tmpURL = allowlistURL.appendingPathExtension("tmp")
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmpURL.path), ".tmp should not remain")

        // File on disk has both rules and is parseable
        let raw = try readRawRules()
        XCTAssertEqual(raw.count, 2)
    }

    func testDebounceReload() async throws {
        // monitoring enabled for this test
        let store = makeStore(startMonitoring: true)
        // Initial load already happened; record that as baseline so subsequent
        // reloads are easy to count.
        let baseline = store.reloadCount

        // Three quick external writes (Python hook / settings UI / etc.)
        for value in ["ls", "git", "find"] {
            try writeRulesDirectly([
                [
                    "id": UUID().uuidString,
                    "toolName": "Bash",
                    "projectPath": "/x",
                    "scope": "always",
                    "enabled": true,
                    "matcher": ["kind": "binaryPrefix", "value": value],
                    "createdAt": Date().timeIntervalSince1970
                ]
            ])
            try await Task.sleep(for: .milliseconds(40))
        }

        // Wait > 200ms debounce window for the coalesced reload to fire.
        try await Task.sleep(for: .milliseconds(450))

        let reloads = store.reloadCount - baseline
        XCTAssertEqual(reloads, 1, "expected debounce to coalesce rapid writes into 1 reload, got \(reloads)")
        XCTAssertEqual(store.rules.count, 1)
        XCTAssertEqual(store.rules.first?.matcher.value, "find")
    }
}
