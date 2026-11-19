import XCTest
@testable import ReminderApp

private final class FakeNotifier: EventNotifying {
    var canDeliver = false
    var permissionAsks = 0
    var scheduled: [[PlannedAlert]] = []

    func requestPermission() { permissionAsks += 1 }
    func reschedule(_ alerts: [PlannedAlert]) { scheduled.append(alerts) }
}

final class EventTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        suiteName = "EventTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func makeStore(_ notifier: FakeNotifier, now: Date) -> EventStore {
        EventStore(defaults: defaults, storageKey: "events", notifier: notifier, now: now, runsTimer: false)
    }

    // MARK: Format

    func testAlertText() {
        XCTAssertEqual(EventFormat.alertText(0), "At time of event")
        XCTAssertEqual(EventFormat.alertText(1), "1 minute before")
        XCTAssertEqual(EventFormat.alertText(15), "15 minutes before")
        XCTAssertEqual(EventFormat.alertText(90), "90 minutes before")
        XCTAssertEqual(EventFormat.alertText(120), "2 hours before")
        XCTAssertEqual(EventFormat.alertText(1_440), "1 day before")
        XCTAssertEqual(EventFormat.alertText(10_080), "1 week before")
    }

    func testAlertBody() {
        let start = date(20, 14)
        XCTAssertEqual(EventFormat.alertBody(minutesBefore: 0, start: start, calendar: calendar), "Starting now · 14:00")
        XCTAssertEqual(EventFormat.alertBody(minutesBefore: 30, start: start, calendar: calendar), "Starts in 30 minutes · 14:00")
    }

    func testCleanAlertsSortsDropsRepeatsAndCapsAtFive() {
        XCTAssertEqual(EventItem.cleanAlerts([30, 10, 30, -5, 99_999, 0, 5, 60, 120]), [0, 5, 10, 30, 60])
    }

    func testCombineAndOvernightEnd() {
        let day = date(20, 3)
        let time = date(1, 23, 30)
        let start = EventFormat.combine(day: day, time: time, calendar: calendar)
        XCTAssertEqual(start, date(20, 23, 30))

        let end = EventFormat.endDate(start: start, endTime: date(1, 1), calendar: calendar)
        XCTAssertEqual(end, date(21, 1))
        let event = EventItem(title: "Late", startDate: start, endDate: end)
        XCTAssertEqual(EventFormat.timeRangeText(event, calendar: calendar), "23:30 → 01:00 (+1 day)")
    }

    // MARK: Planner

    func testPlannerKeepsOnlyFutureAlertsSoonestFirst() {
        let a = EventItem(title: "A", startDate: date(20, 14), endDate: date(20, 15), alertMinutes: [0, 60, 1_440])
        let b = EventItem(title: "B", startDate: date(20, 13), endDate: date(20, 13), alertMinutes: [10])
        let now = date(20, 12)

        let planned = EventAlertPlanner.upcomingAlerts(for: [a, b], after: now)
        XCTAssertEqual(planned.map(\.fireDate), [date(20, 12, 50), date(20, 13), date(20, 14)])
        XCTAssertEqual(planned.map(\.title), ["B", "A", "A"])
    }

    func testPlannerRespectsLimit() {
        let events = (0..<30).map {
            EventItem(title: "E\($0)", startDate: date(25, 9).addingTimeInterval(Double($0) * 3_600),
                      endDate: date(25, 9), alertMinutes: [0, 10, 30])
        }
        XCTAssertEqual(EventAlertPlanner.upcomingAlerts(for: events, after: date(20, 9)).count, 60)
    }

    func testAlertsDueWindow() {
        let e = EventItem(title: "A", startDate: date(20, 14), endDate: date(20, 14), alertMinutes: [0, 15])
        let due = EventAlertPlanner.alertsDue(for: [e], after: date(20, 13, 40), upTo: date(20, 13, 50))
        XCTAssertEqual(due.map(\.minutesBefore), [15])
    }

    // MARK: Store

    func testAddSavesSortsAndSchedules() {
        let notifier = FakeNotifier()
        let store = makeStore(notifier, now: date(19, 9))
        XCTAssertTrue(store.add(title: "  Dentist ", start: date(21, 10), end: date(21, 11), alertMinutes: [30], notes: ""))
        XCTAssertTrue(store.add(title: "Call", start: date(20, 10), end: date(20, 10), alertMinutes: [], notes: " hi "))

        XCTAssertEqual(store.events.map(\.title), ["Call", "Dentist"])
        XCTAssertEqual(store.events.first?.notes, "hi")
        XCTAssertEqual(notifier.permissionAsks, 1, "Only the event with an alert asks for permission")
        XCTAssertFalse(notifier.scheduled.isEmpty)

        let reloaded = makeStore(FakeNotifier(), now: date(19, 9))
        XCTAssertEqual(reloaded.events, store.events)
    }

    func testUpdateAndDelete() {
        let store = makeStore(FakeNotifier(), now: date(19, 9))
        store.add(title: "Old", start: date(21, 10), end: date(21, 11), alertMinutes: [10], notes: "")
        let id = store.events[0].id
        XCTAssertTrue(store.update(id, title: "New", start: date(22, 9), end: date(22, 9, 30), alertMinutes: [0], notes: "x"))
        XCTAssertEqual(store.events[0].title, "New")
        XCTAssertEqual(store.events[0].alertMinutes, [0])
        XCTAssertEqual(store.events[0].id, id)

        store.delete(id)
        XCTAssertTrue(store.events.isEmpty)
        XCTAssertFalse(store.update(id, title: "Gone", start: date(22, 9), end: date(22, 9), alertMinutes: [], notes: ""))
    }

    func testUpcomingAndPast() {
        let store = makeStore(FakeNotifier(), now: date(19, 9))
        store.add(title: "Done", start: date(18, 9), end: date(18, 10), alertMinutes: [], notes: "")
        store.add(title: "Now", start: date(19, 8), end: date(19, 10), alertMinutes: [], notes: "")
        store.add(title: "Later", start: date(20, 9), end: date(20, 10), alertMinutes: [], notes: "")
        XCTAssertEqual(store.upcoming(at: date(19, 9)).map(\.title), ["Now", "Later"])
        XCTAssertEqual(store.past(at: date(19, 9)).map(\.title), ["Done"])
    }

    func testInAppAlertsOnlyWhenNotificationsAreOff() {
        let notifier = FakeNotifier()
        let store = makeStore(notifier, now: date(20, 13, 40))
        store.add(title: "Talk", start: date(20, 14), end: date(20, 15), alertMinutes: [15], notes: "")

        notifier.canDeliver = true
        store.checkInAppAlerts(now: date(20, 13, 30))
        XCTAssertTrue(store.inAppAlerts.isEmpty)

        notifier.canDeliver = false
        store.checkInAppAlerts(now: date(20, 13, 46))
        XCTAssertEqual(store.inAppAlerts.map(\.title), ["Talk"])

        store.checkInAppAlerts(now: date(20, 13, 50))
        XCTAssertEqual(store.inAppAlerts.count, 1, "The same alert is not shown twice")
        store.dismissInAppAlert()
        XCTAssertTrue(store.inAppAlerts.isEmpty)
    }
}
