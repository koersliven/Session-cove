import XCTest
import AppKit
@testable import SessionCove

/// Unit tests for `PetAnchorGeometry.clamp`.
///
/// Anchor persistence (save/load) is now owned by `CoveSettings.petAnchorPoint`
/// and exercised in `CoveSettingsTests`. What remains here is the pure
/// screen-geometry clamp — kept controller-side because `CoveSettings` is not
/// aware of `NSScreen.visibleFrame`.
final class AnchorPersistenceTests: XCTestCase {

    // MARK: - Clamp (off-screen recovery)

    func testClampOffscreenPastRightAndBottomEdges() {
        let visible = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let petSize = NSSize(width: 48, height: 48)

        let r = PetAnchorGeometry.clamp(NSPoint(x: 9999, y: 200), petSize: petSize, into: visible)
        XCTAssertEqual(r.x, 1000 - 48, accuracy: 1e-6)
        XCTAssertEqual(r.y, 200, accuracy: 1e-6)

        let b = PetAnchorGeometry.clamp(NSPoint(x: 100, y: -50), petSize: petSize, into: visible)
        XCTAssertEqual(b.x, 100, accuracy: 1e-6)
        XCTAssertEqual(b.y, 0, accuracy: 1e-6)

        let lt = PetAnchorGeometry.clamp(NSPoint(x: -10, y: 9999), petSize: petSize, into: visible)
        XCTAssertEqual(lt.x, 0, accuracy: 1e-6)
        XCTAssertEqual(lt.y, 800 - 48, accuracy: 1e-6)
    }

    func testClampLeavesInsidePointsUntouched() {
        let visible = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let petSize = NSSize(width: 48, height: 48)

        let inside = NSPoint(x: 200, y: 300)
        let result = PetAnchorGeometry.clamp(inside, petSize: petSize, into: visible)
        XCTAssertEqual(result.x, inside.x, accuracy: 1e-6)
        XCTAssertEqual(result.y, inside.y, accuracy: 1e-6)
    }

    func testClampHandlesNonZeroOriginVisibleFrame() {
        // Multi-monitor: secondary screen positioned to the left and slightly below
        // the primary. visible.minX = -1440, visible.maxX = 0,
        // visible.minY = -200, visible.maxY = 700.
        let visible = NSRect(x: -1440, y: -200, width: 1440, height: 900)
        let petSize = NSSize(width: 48, height: 48)

        let r = PetAnchorGeometry.clamp(NSPoint(x: 9999, y: 9999), petSize: petSize, into: visible)
        XCTAssertEqual(r.x, -48, accuracy: 1e-6)
        XCTAssertEqual(r.y, 652, accuracy: 1e-6)

        let bottom = PetAnchorGeometry.clamp(NSPoint(x: -1000, y: -9999), petSize: petSize, into: visible)
        XCTAssertEqual(bottom.x, -1000, accuracy: 1e-6)
        XCTAssertEqual(bottom.y, -200, accuracy: 1e-6)
    }
}
