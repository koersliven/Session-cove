import XCTest
@testable import SessionCove

final class SessionParserTests: XCTestCase {
    func testParseNonexistentFile() {
        let record = SessionParser.parse(
            filePath: "/nonexistent/path.jsonl",
            projectDirEncoded: "-Users-lipu-Work-hermes-agent"
        )
        XCTAssertNil(record)
    }
}
