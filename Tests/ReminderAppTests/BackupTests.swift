import AppKit
import XCTest
@testable import ReminderApp

private final class SilentNotifier: EventNotifying {
    var canDeliver = true
    func requestPermission() {}
    func reschedule(_ alerts: [PlannedAlert]) {}
}

final class BackupTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var folder: URL!

    override func setUp() {
        super.setUp()
        suiteName = "BackupTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(suiteName, isDirectory: true)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    private func makeService(prefix: String) -> BackupService {
        BackupService(
            events: EventStore(defaults: defaults, storageKey: "\(prefix)events", notifier: SilentNotifier(), runsTimer: false),
            tasks: TaskStore(defaults: defaults, storageKey: "\(prefix)tasks",
                             imageStore: TaskImageStore(directoryURL: folder.appendingPathComponent("\(prefix)images"))),
            timeBlocks: TimeBlockSettings(defaults: defaults, storageKey: "\(prefix)blocks"),
            worldClocks: WorldClockStore(defaults: defaults, storageKey: "\(prefix)clocks"),
            images: TaskImageStore(directoryURL: folder.appendingPathComponent("\(prefix)images"))
        )
    }

    private func pngData() -> Data {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 4, height: 4).fill()
        image.unlockFocus()
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        return rep.representation(using: .png, properties: [:])!
    }

    private func fill(_ service: BackupService) throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        service.events.add(title: "Dentist", start: start, end: start.addingTimeInterval(3_600), alertMinutes: [0, 30], notes: "Bring card")
        try service.images.restoreImage(pngData(), named: "photo.png")
        service.tasks.replaceAll(with: [TaskItem(title: "Focus", startSeconds: 9 * 3_600, endSeconds: 12 * 3_600, repeatDays: [2, 3], imageFilename: "photo.png")])
        service.timeBlocks.update(TimeBlockRange(startHour: 7, endHour: 8), for: .earlyMorning)
        service.worldClocks.add(cityName: "Tokyo", timeZoneID: "Asia/Tokyo")
        service.worldClocks.setShowsInDisplay(false)
    }

    func testRoundTripRestoresEverything() throws {
        let source = makeService(prefix: "a.")
        try fill(source)
        let data = try BackupCodec.encode(source.makeBackup())
        let file = try BackupCodec.decode(data)
        XCTAssertEqual(file.summary, "1 event, 1 reminder, 1 world clock, 1 photo")

        let target = makeService(prefix: "b.")
        let result = try target.restore(file, scope: .everything)

        XCTAssertEqual(result, RestoreResult(events: 1, tasks: 1, worldClocks: 1, photos: 1, missingPhotos: 0))
        XCTAssertEqual(target.events.events, source.events.events)
        XCTAssertEqual(target.tasks.tasks, source.tasks.tasks)
        XCTAssertEqual(target.timeBlocks.range(for: .earlyMorning), TimeBlockRange(startHour: 7, endHour: 8))
        XCTAssertEqual(target.worldClocks.clocks, source.worldClocks.clocks)
        XCTAssertFalse(target.worldClocks.showsInDisplay)
        XCTAssertNotNil(target.images.imageData(named: "photo.png"))
    }

    func testEventsOnlyLeavesTheRestAlone() throws {
        let source = makeService(prefix: "a.")
        try fill(source)
        let file = try BackupCodec.decode(BackupCodec.encode(source.makeBackup()))

        let target = makeService(prefix: "b.")
        target.tasks.replaceAll(with: [TaskItem(title: "Keep me", startSeconds: 0, endSeconds: 0)])
        try target.restore(file, scope: .eventsOnly)

        XCTAssertEqual(target.events.events.map(\.title), ["Dentist"])
        XCTAssertEqual(target.tasks.tasks.map(\.title), ["Keep me"])
        XCTAssertTrue(target.worldClocks.clocks.isEmpty)
    }

    func testMissingPhotoIsDroppedNotBroken() throws {
        var file = BackupFile(
            exportedAt: Date(),
            events: [],
            tasks: [TaskItem(title: "T", startSeconds: 0, endSeconds: 0, imageFilename: "gone.jpg")]
        )
        file.photos = ["../escape.jpg": pngData()]
        let target = makeService(prefix: "b.")
        let result = try target.restore(file, scope: .everything)
        XCTAssertEqual(result.missingPhotos, 1)
        XCTAssertNil(target.tasks.tasks.first?.imageFilename)
    }

    func testRefusesPhotoNamesOutsideTheFolder() {
        let images = TaskImageStore(directoryURL: folder.appendingPathComponent("imgs"))
        XCTAssertThrowsError(try images.restoreImage(pngData(), named: "../escape.png"))
        XCTAssertThrowsError(try images.restoreImage(Data("not an image".utf8), named: "fake.jpg"))
    }

    func testRejectsOtherFiles() {
        XCTAssertThrowsError(try BackupCodec.decode(Data("{\"hello\": 1}".utf8))) {
            XCTAssertEqual($0 as? BackupError, .notABackup)
        }
        XCTAssertThrowsError(try BackupCodec.decode(Data("{\"format\":\"Other\",\"version\":1,\"events\":[]}".utf8))) {
            XCTAssertEqual($0 as? BackupError, .notABackup)
        }
        XCTAssertThrowsError(try BackupCodec.decode(Data("{\"format\":\"ScreenReminderBackup\",\"version\":99,\"events\":[]}".utf8))) {
            XCTAssertEqual($0 as? BackupError, .newerVersion(99))
        }
        XCTAssertThrowsError(try BackupCodec.decode(Data("nope".utf8)))
    }

    func testEventsOnlyFileIsAccepted() throws {
        let json = """
        {"format":"ScreenReminderBackup","version":1,"events":[{"id":"\(UUID().uuidString)","title":"X",
        "startDate":"2026-12-01T10:00:00Z","endDate":"2026-12-01T11:00:00Z","alertMinutes":[10],
        "notes":"","createdAt":"2026-11-19T10:00:00Z"}]}
        """
        let file = try BackupCodec.decode(Data(json.utf8))
        XCTAssertEqual(file.events.count, 1)
        XCTAssertTrue(file.tasks.isEmpty)
    }

    func testSafetyCopyIsWritten() throws {
        let service = makeService(prefix: "a.")
        try fill(service)
        let url = try service.writeSafetyCopy(into: folder.appendingPathComponent("Backups"))
        let file = try BackupCodec.decode(Data(contentsOf: url))
        XCTAssertEqual(file.events.map(\.title), ["Dentist"])
    }
}
