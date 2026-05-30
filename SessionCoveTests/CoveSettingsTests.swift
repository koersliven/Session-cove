import XCTest
@testable import SessionCove

@MainActor
final class CoveSettingsTests: XCTestCase {
    private static let suiteName = "com.session-cove.tests.CoveSettings"
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        // Fresh, isolated UserDefaults suite per test so we never touch the
        // production .standard domain.
        UserDefaults().removePersistentDomain(forName: Self.suiteName)
        defaults = UserDefaults(suiteName: Self.suiteName)!
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: Self.suiteName)
        defaults = nil
        try await super.tearDown()
    }

    func testDefaultValues() {
        let settings = CoveSettings(defaults: defaults)

        XCTAssertEqual(settings.displayMode, .pet)
        XCTAssertEqual(settings.contentFontSize, 13.0)
        XCTAssertFalse(settings.launchAtLogin)
        XCTAssertTrue(settings.soundEnabled)
        XCTAssertEqual(settings.soundVolume, 0.6, accuracy: 0.0001)
        XCTAssertNil(settings.preferredScreenID)
        XCTAssertEqual(settings.petAnchorMode, .lastPosition)
        XCTAssertNil(settings.petAnchorPoint)
        XCTAssertEqual(settings.notchTrigger, .hover)
        XCTAssertFalse(settings.showArchivedSessions)
    }

    func testPersistence() {
        let settings = CoveSettings(defaults: defaults)
        settings.displayMode = .notch
        settings.contentFontSize = 15.0
        settings.soundEnabled = false
        settings.soundVolume = 0.25
        settings.petAnchorMode = .topCenter
        settings.petAnchorPoint = NSPoint(x: 120, y: 240)
        settings.notchTrigger = .click
        settings.showArchivedSessions = true

        // Reload from the same defaults to confirm round-trip persistence.
        let restored = CoveSettings(defaults: defaults)
        XCTAssertEqual(restored.displayMode, .notch)
        XCTAssertEqual(restored.contentFontSize, 15.0)
        XCTAssertFalse(restored.soundEnabled)
        XCTAssertEqual(restored.soundVolume, 0.25, accuracy: 0.0001)
        XCTAssertEqual(restored.petAnchorMode, .topCenter)
        XCTAssertEqual(restored.petAnchorPoint?.x, 120)
        XCTAssertEqual(restored.petAnchorPoint?.y, 240)
        XCTAssertEqual(restored.notchTrigger, .click)
        XCTAssertTrue(restored.showArchivedSessions)
    }

    func testFontSizeIsClampedToRange() {
        let settings = CoveSettings(defaults: defaults)
        settings.contentFontSize = 99.0
        XCTAssertEqual(settings.contentFontSize, 17.0)
        settings.contentFontSize = 1.0
        XCTAssertEqual(settings.contentFontSize, 11.0)
    }

    func testPetAnchorPointFormatMatchesPetAnchorPersistence() {
        // PR 1.C will transfer ownership of this UserDefaults key from
        // PetAnchorPersistence -> CoveSettings. Both read/write [Double]; this
        // test guards against an accidental format divergence.
        let settings = CoveSettings(defaults: defaults)
        settings.petAnchorPoint = NSPoint(x: 33, y: 77)

        let stored = defaults.array(forKey: "covePetAnchorPoint") as? [Double]
        XCTAssertEqual(stored, [33.0, 77.0])
    }

    func testNotificationOnDisplayModeChange() {
        let settings = CoveSettings(defaults: defaults)
        let exp = expectation(forNotification: .coveDisplayModeDidChange,
                              object: settings,
                              handler: nil)
        settings.displayMode = .notch
        wait(for: [exp], timeout: 1.0)
    }

    func testNoNotificationWhenDisplayModeAssignedSameValue() {
        let settings = CoveSettings(defaults: defaults)
        let exp = expectation(forNotification: .coveDisplayModeDidChange,
                              object: settings,
                              handler: nil)
        exp.isInverted = true
        settings.displayMode = .pet  // unchanged
        wait(for: [exp], timeout: 0.3)
    }

    func testBootstrapNoNotification() {
        // Seed defaults so init has work to do.
        defaults.set(CoveSettings.DisplayMode.notch.rawValue,
                     forKey: "coveDisplayMode")

        let exp = expectation(forNotification: .coveDisplayModeDidChange,
                              object: nil,
                              handler: nil)
        exp.isInverted = true

        // init must not post coveDisplayModeDidChange while loading from store.
        let settings = CoveSettings(defaults: defaults)
        XCTAssertEqual(settings.displayMode, .notch)

        wait(for: [exp], timeout: 0.3)
    }
}
