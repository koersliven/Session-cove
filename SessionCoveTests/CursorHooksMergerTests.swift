import XCTest
@testable import SessionCove

final class CursorHooksMergerTests: XCTestCase {
    private let bridgeCmd = "/usr/bin/python3 /Library/SessionCove/session_cove_claude_hook.py --provider cursor stop"

    func testAppendsToEmptyDocument() {
        let merged = CursorHooksMerger.merged(
            into: [:],
            sessionCoveCommand: bridgeCmd
        )

        let stop = merged["stop"] as? [[String: Any]]
        XCTAssertEqual(stop?.count, 1)
        XCTAssertEqual(stop?.first?["type"] as? String, "command")
        XCTAssertEqual(stop?.first?["command"] as? String, bridgeCmd)
    }

    func testPreservesUserEntriesAndExtraFields() {
        let userEntry: [String: Any] = [
            "type": "command",
            "command": "/Users/me/r2c-audit.sh",
            "description": "audit"
        ]
        let existing: [String: Any] = ["stop": [userEntry]]

        let merged = CursorHooksMerger.merged(
            into: existing,
            sessionCoveCommand: bridgeCmd
        )

        let stop = merged["stop"] as? [[String: Any]]
        XCTAssertEqual(stop?.count, 2)
        XCTAssertEqual(stop?.first?["command"] as? String, "/Users/me/r2c-audit.sh")
        // Extra "description" field must survive verbatim.
        XCTAssertEqual(stop?.first?["description"] as? String, "audit")
        XCTAssertEqual(stop?.last?["command"] as? String, bridgeCmd)
    }

    func testIdempotentReinstallReplacesPriorSessionCoveEntry() {
        let oldBridge = "/old/path/session_cove_claude_hook.py --provider cursor stop"
        let userEntry: [String: Any] = [
            "type": "command",
            "command": "/Users/me/r2c-audit.sh"
        ]
        let oldOurs: [String: Any] = [
            "type": "command",
            "command": oldBridge
        ]
        let existing: [String: Any] = ["stop": [userEntry, oldOurs]]

        let merged = CursorHooksMerger.merged(
            into: existing,
            sessionCoveCommand: bridgeCmd
        )

        let stop = merged["stop"] as? [[String: Any]]
        XCTAssertEqual(stop?.count, 2, "expected only one Session Cove entry after reinstall")
        XCTAssertEqual(stop?.first?["command"] as? String, "/Users/me/r2c-audit.sh")
        XCTAssertEqual(stop?.last?["command"] as? String, bridgeCmd)
    }

    func testUnsubscribedEventsAreUntouched() {
        let userEntry: [String: Any] = [
            "type": "command",
            "command": "/Users/me/start.sh"
        ]
        let existing: [String: Any] = ["sessionStart": [userEntry]]

        let merged = CursorHooksMerger.merged(
            into: existing,
            sessionCoveCommand: bridgeCmd
        )

        // sessionStart array preserved exactly.
        let sessionStart = merged["sessionStart"] as? [[String: Any]]
        XCTAssertEqual(sessionStart?.count, 1)
        XCTAssertEqual(sessionStart?.first?["command"] as? String, "/Users/me/start.sh")

        // stop was created with just our entry.
        let stop = merged["stop"] as? [[String: Any]]
        XCTAssertEqual(stop?.count, 1)
        XCTAssertEqual(stop?.first?["command"] as? String, bridgeCmd)
    }

    func testUnknownShapesArePreservedDefensively() {
        // A non-dict value in the array (shouldn't happen in valid Cursor
        // configs, but the merger should not drop user data).
        let weird: Any = "not-a-dict"
        let existing: [String: Any] = ["stop": [weird]]

        let merged = CursorHooksMerger.merged(
            into: existing,
            sessionCoveCommand: bridgeCmd
        )

        let stop = merged["stop"] as? [Any]
        XCTAssertEqual(stop?.count, 2)
        XCTAssertEqual(stop?.first as? String, "not-a-dict")
        XCTAssertEqual((stop?.last as? [String: Any])?["command"] as? String, bridgeCmd)
    }
}
