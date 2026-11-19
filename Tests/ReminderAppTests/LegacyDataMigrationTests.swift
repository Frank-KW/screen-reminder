import XCTest
@testable import ReminderApp

final class LegacyDataMigrationTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "LegacyDataMigrationTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testCopiesSavedDataOnceAndKeepsNewerValues() {
        let legacy: [String: Any] = [
            "tasks": Data("old-tasks".utf8),
            "worldClocks": Data("old-clocks".utf8),
            "unrelated": "ignored"
        ]
        defaults.set(Data("new-blocks".utf8), forKey: "timeBlockSettings")

        LegacyDataMigration.run(into: defaults, legacyValues: legacy)

        XCTAssertEqual(defaults.data(forKey: "tasks"), Data("old-tasks".utf8))
        XCTAssertEqual(defaults.data(forKey: "worldClocks"), Data("old-clocks".utf8))
        XCTAssertEqual(defaults.data(forKey: "timeBlockSettings"), Data("new-blocks".utf8))
        XCTAssertNil(defaults.object(forKey: "unrelated"))

        // A second run must not bring back data the user has since deleted.
        defaults.removeObject(forKey: "tasks")
        LegacyDataMigration.run(into: defaults, legacyValues: legacy)
        XCTAssertNil(defaults.object(forKey: "tasks"))
    }

    func testNoLegacyDataStillMarksDone() {
        LegacyDataMigration.run(into: defaults, legacyValues: nil)
        XCTAssertTrue(defaults.bool(forKey: LegacyDataMigration.doneKey))
        XCTAssertNil(defaults.object(forKey: "tasks"))
    }
}
