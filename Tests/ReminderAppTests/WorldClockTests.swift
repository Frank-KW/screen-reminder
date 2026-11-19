import XCTest
@testable import ReminderApp

final class WorldClockTests: XCTestCase {
    private let london = TimeZone(identifier: "Europe/London")!
    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
    private let kolkata = TimeZone(identifier: "Asia/Kolkata")!
    private let utc = TimeZone(identifier: "UTC")!

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "WorldClockTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // 2026-11-16 20:00 UTC (London is on UTC in November).
    private var eveningInLondon: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 20))!
    }

    // MARK: Math

    func testCityNameFromIdentifier() {
        XCTAssertEqual(WorldClockMath.cityName(fromIdentifier: "America/New_York"), "New York")
        XCTAssertEqual(WorldClockMath.cityName(fromIdentifier: "America/Argentina/Buenos_Aires"), "Buenos Aires")
        XCTAssertEqual(WorldClockMath.cityName(fromIdentifier: "UTC"), "UTC")
    }

    func testOffsetText() {
        XCTAssertEqual(WorldClockMath.offsetText(seconds: 0), "+0 hrs")
        XCTAssertEqual(WorldClockMath.offsetText(seconds: 3_600), "+1 hr")
        XCTAssertEqual(WorldClockMath.offsetText(seconds: 9 * 3_600), "+9 hrs")
        XCTAssertEqual(WorldClockMath.offsetText(seconds: -8 * 3_600), "-8 hrs")
        XCTAssertEqual(WorldClockMath.offsetText(seconds: 19_800), "+5:30 hrs")
        XCTAssertEqual(WorldClockMath.offsetText(seconds: -9_000), "-2:30 hrs")
    }

    func testRelativeTextAcrossMidnight() {
        let date = eveningInLondon
        XCTAssertEqual(WorldClockMath.relativeText(for: tokyo, at: date, relativeTo: london), "Tomorrow, +9 hrs")
        XCTAssertEqual(WorldClockMath.relativeText(for: losAngeles, at: date, relativeTo: london), "Today, -8 hrs")
        XCTAssertEqual(WorldClockMath.relativeText(for: kolkata, at: date, relativeTo: london), "Tomorrow, +5:30 hrs")
        XCTAssertEqual(WorldClockMath.relativeText(for: london, at: date, relativeTo: london), "Today, +0 hrs")
        XCTAssertEqual(WorldClockMath.dayOffset(of: losAngeles, at: date, relativeTo: tokyo), -1)
    }

    func testHandAngles() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 15, minute: 30, second: 45))!

        let angles = WorldClockMath.handAngles(in: utc, at: date)
        XCTAssertEqual(angles.hour, 105, accuracy: 0.001)
        XCTAssertEqual(angles.minute, 184.5, accuracy: 0.001)
        XCTAssertEqual(angles.second, 270, accuracy: 0.001)

        let tokyoAngles = WorldClockMath.handAngles(in: tokyo, at: date) // 00:30:45
        XCTAssertEqual(tokyoAngles.hour, 15, accuracy: 0.001)
    }

    func testDaytimeFace() {
        let date = eveningInLondon
        XCTAssertFalse(WorldClockMath.isDaytime(in: london, at: date)) // 20:00
        XCTAssertTrue(WorldClockMath.isDaytime(in: losAngeles, at: date)) // 12:00
        XCTAssertFalse(WorldClockMath.isDaytime(in: tokyo, at: date)) // 05:00
    }

    func testSearchFindsZoneCitiesAndAliases() {
        let all = WorldClockMath.allSuggestions()

        let hong = WorldClockMath.search("hong", in: all)
        XCTAssertEqual(hong.first?.timeZoneID, "Asia/Hong_Kong")

        let beijing = WorldClockMath.search("Beijing", in: all)
        XCTAssertEqual(beijing.first, CitySuggestion(name: "Beijing", timeZoneID: "Asia/Shanghai"))

        let newYork = WorldClockMath.search("new york", in: all)
        XCTAssertEqual(newYork.first?.timeZoneID, "America/New_York")

        let sao = WorldClockMath.search("sao paulo", in: all)
        XCTAssertTrue(sao.contains { $0.timeZoneID == "America/Sao_Paulo" })

        XCTAssertEqual(WorldClockMath.search("  ", in: all).count, all.count)
        XCTAssertTrue(WorldClockMath.search("zzzz-no-city", in: all).isEmpty)
        XCTAssertTrue(all.allSatisfy { TimeZone(identifier: $0.timeZoneID) != nil })
    }

    // MARK: Store

    func testAddEditRemoveAndPersist() {
        let store = WorldClockStore(defaults: defaults)
        XCTAssertTrue(store.clocks.isEmpty)
        XCTAssertTrue(store.showsInDisplay)

        XCTAssertTrue(store.add(cityName: "Hong Kong", timeZoneID: "Asia/Hong_Kong"))
        XCTAssertTrue(store.add(cityName: "  ", timeZoneID: "America/New_York"))
        XCTAssertEqual(store.clocks.map(\.cityName), ["Hong Kong", "New York"])

        let newYork = store.clocks[1]
        XCTAssertTrue(store.update(newYork.id, cityName: "  Mum's   office ", timeZoneID: "Europe/Paris"))
        XCTAssertEqual(store.clocks[1].cityName, "Mum's office")
        XCTAssertEqual(store.clocks[1].timeZoneID, "Europe/Paris")

        store.move(newYork.id, by: -1)
        XCTAssertEqual(store.clocks.map(\.cityName), ["Mum's office", "Hong Kong"])

        store.setShowsInDisplay(false)

        let reloaded = WorldClockStore(defaults: defaults)
        XCTAssertEqual(reloaded.clocks, store.clocks)
        XCTAssertFalse(reloaded.showsInDisplay)

        reloaded.delete(newYork.id)
        XCTAssertEqual(reloaded.clocks.map(\.cityName), ["Hong Kong"])
        XCTAssertEqual(WorldClockStore(defaults: defaults).clocks.map(\.cityName), ["Hong Kong"])
    }

    func testRejectsBadTimeZoneAndCapsCount() {
        let store = WorldClockStore(defaults: defaults)
        XCTAssertFalse(store.add(cityName: "Nowhere", timeZoneID: "Mars/Olympus_Mons"))

        for _ in 0..<WorldClockStore.maxClocks {
            XCTAssertTrue(store.add(cityName: "Tokyo", timeZoneID: "Asia/Tokyo"))
        }
        XCTAssertFalse(store.canAddMore)
        XCTAssertFalse(store.add(cityName: "One too many", timeZoneID: "Asia/Tokyo"))
        XCTAssertEqual(store.clocks.count, WorldClockStore.maxClocks)

        XCTAssertFalse(store.update(store.clocks[0].id, cityName: "X", timeZoneID: "Bad/Zone"))
        XCTAssertEqual(store.clocks[0].timeZoneID, "Asia/Tokyo")
    }
}
