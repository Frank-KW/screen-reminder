import AppKit
import XCTest
@testable import ReminderApp

final class TimeUtilsTests: XCTestCase {
    func testIsActiveSameDayRange() {
        let start = 9 * 3600
        let end = 17 * 3600

        XCTAssertTrue(TimeUtils.isActive(startSeconds: start, endSeconds: end, nowSeconds: 9 * 3600))
        XCTAssertTrue(TimeUtils.isActive(startSeconds: start, endSeconds: end, nowSeconds: 12 * 3600))
        XCTAssertTrue(TimeUtils.isActive(startSeconds: start, endSeconds: end, nowSeconds: 17 * 3600))
        XCTAssertFalse(TimeUtils.isActive(startSeconds: start, endSeconds: end, nowSeconds: 8 * 3600))
        XCTAssertFalse(TimeUtils.isActive(startSeconds: start, endSeconds: end, nowSeconds: 18 * 3600))
    }

    func testIsActiveOvernightRange() {
        let start = 22 * 3600
        let end = 2 * 3600

        XCTAssertTrue(TimeUtils.isActive(startSeconds: start, endSeconds: end, nowSeconds: 23 * 3600))
        XCTAssertTrue(TimeUtils.isActive(startSeconds: start, endSeconds: end, nowSeconds: 1 * 3600))
        XCTAssertFalse(TimeUtils.isActive(startSeconds: start, endSeconds: end, nowSeconds: 12 * 3600))
    }

    func testEqualStartAndEndRepresentsAllDay() {
        XCTAssertTrue(TimeUtils.isActive(startSeconds: 9 * 3600, endSeconds: 9 * 3600, nowSeconds: 2 * 3600))
        XCTAssertEqual(TaskItem(title: "All day", startSeconds: 9 * 3600, endSeconds: 9 * 3600).timeRangeText, "All day")
    }

    func testOvernightScheduleUsesTheStartingWeekdayAfterMidnight() {
        let mondayAtElevenPM = date(year: 2026, month: 8, day: 24, hour: 23)
        let tuesdayAtOneAM = date(year: 2026, month: 8, day: 25, hour: 1)
        let mondayOnly = [Weekday.monday.rawValue]

        XCTAssertTrue(TimeUtils.matchesSchedule(
            startSeconds: 22 * 3600,
            endSeconds: 2 * 3600,
            repeatDays: mondayOnly,
            at: mondayAtElevenPM
        ))
        XCTAssertTrue(TimeUtils.matchesSchedule(
            startSeconds: 22 * 3600,
            endSeconds: 2 * 3600,
            repeatDays: mondayOnly,
            at: tuesdayAtOneAM
        ))
    }

    func testProgressAcrossMidnight() {
        XCTAssertEqual(
            TimeUtils.progress(startSeconds: 22 * 3600, endSeconds: 2 * 3600, nowSeconds: 0),
            0.5,
            accuracy: 0.001
        )
    }

    func testActiveTaskPrefersTheMostRecentlyStartedOverlap() {
        let suiteName = "TimeUtilsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = TaskStore(defaults: defaults, storageKey: "testTasks")

        store.addTask(
            title: "Overnight",
            start: date(year: 2026, month: 8, day: 24, hour: 22),
            end: date(year: 2026, month: 8, day: 25, hour: 2),
            repeatDays: []
        )
        store.addTask(
            title: "Early task",
            start: date(year: 2026, month: 8, day: 25, hour: 1),
            end: date(year: 2026, month: 8, day: 25, hour: 3),
            repeatDays: []
        )

        XCTAssertEqual(store.activeTask(at: date(year: 2026, month: 8, day: 25, hour: 1, minute: 30))?.title, "Early task")
    }

    func testTimeStringFormatting() {
        XCTAssertEqual(TimeUtils.timeString(from: 0), "00:00")
        XCTAssertEqual(TimeUtils.timeString(from: 9 * 3600 + 5 * 60), "09:05")
        XCTAssertEqual(TimeUtils.timeString(from: 23 * 3600 + 59 * 60), "23:59")
    }

    func testTimeBlocksHaveRequestedNamesAndUKDefaults() {
        XCTAssertEqual(TimeBlock.allCases.map(\.displayName), [
            "Early Morning",
            "Morning Work Block",
            "Lunch Break",
            "Afternoon Work Block",
            "Wrap-up",
            "After Work",
            "Wind-down",
            "Sleep",
            "Working Hours"
        ])

        XCTAssertEqual(TimeBlock.ukDefaultRanges[.earlyMorning], TimeBlockRange(startHour: 6, endHour: 9))
        XCTAssertEqual(TimeBlock.ukDefaultRanges[.morningWorkBlock], TimeBlockRange(startHour: 9, endHour: 12))
        XCTAssertEqual(TimeBlock.ukDefaultRanges[.lunchBreak], TimeBlockRange(startHour: 12, endHour: 13))
        XCTAssertEqual(TimeBlock.ukDefaultRanges[.afternoonWorkBlock], TimeBlockRange(startHour: 13, endHour: 17))
        XCTAssertEqual(TimeBlock.ukDefaultRanges[.wrapUp], TimeBlockRange(startHour: 17, endHour: 17, endMinute: 30))
        XCTAssertEqual(TimeBlock.ukDefaultRanges[.afterWork], TimeBlockRange(startHour: 17, startMinute: 30, endHour: 20))
        XCTAssertEqual(TimeBlock.ukDefaultRanges[.windDown], TimeBlockRange(startHour: 20, endHour: 22, endMinute: 30))
        XCTAssertEqual(TimeBlock.ukDefaultRanges[.sleep], TimeBlockRange(startHour: 22, startMinute: 30, endHour: 6))
        XCTAssertEqual(TimeBlock.ukDefaultRanges[.workingHours], TimeBlockRange(startHour: 9, endHour: 17, endMinute: 30))
    }

    func testTimeBlockSettingsPersistAndRestoreUKDefaults() {
        let suiteName = "TimeBlockSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let storageKey = "testTimeBlocks"
        let settings = TimeBlockSettings(defaults: defaults, storageKey: storageKey)
        let customRange = TimeBlockRange(startHour: 5, startMinute: 30, endHour: 8, endMinute: 15)
        settings.update(customRange, for: .earlyMorning)

        let reloaded = TimeBlockSettings(defaults: defaults, storageKey: storageKey)
        XCTAssertEqual(reloaded.range(for: .earlyMorning), customRange)
        XCTAssertEqual(reloaded.range(for: .workingHours), TimeBlock.ukDefaultRanges[.workingHours])

        reloaded.restoreUKDefaults()
        XCTAssertEqual(reloaded.range(for: .earlyMorning), TimeBlock.ukDefaultRanges[.earlyMorning])
    }

    func testSelectedTimeBlockIsPersistedWithReminder() throws {
        let suiteName = "TaskTimeBlockTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = TaskStore(defaults: defaults, storageKey: "timeBlockTasks")
        XCTAssertTrue(store.addTask(
            title: "Sleep",
            start: date(year: 2026, month: 8, day: 27, hour: 22, minute: 30),
            end: date(year: 2026, month: 8, day: 28, hour: 6),
            repeatDays: [],
            timeBlock: .sleep
        ))

        var reloaded = TaskStore(defaults: defaults, storageKey: "timeBlockTasks")
        var task = try XCTUnwrap(reloaded.tasks.first)
        XCTAssertEqual(task.timeBlock, .sleep)
        XCTAssertEqual(task.scheduleTimeText, "Sleep · 22:30 → 06:00")

        XCTAssertTrue(reloaded.updateTask(
            task,
            title: task.title,
            start: date(year: 2026, month: 8, day: 27, hour: 23, minute: 15),
            end: date(year: 2026, month: 8, day: 28, hour: 6, minute: 45),
            repeatDays: [],
            imageFilename: nil,
            timeBlock: .sleep
        ))

        reloaded = TaskStore(defaults: defaults, storageKey: "timeBlockTasks")
        task = try XCTUnwrap(reloaded.tasks.first)
        XCTAssertEqual(task.timeBlock, .sleep)
        XCTAssertEqual(task.startSeconds, 23 * 3_600 + 15 * 60)
        XCTAssertEqual(task.endSeconds, 6 * 3_600 + 45 * 60)
        XCTAssertEqual(task.scheduleTimeText, "Sleep · 23:15 → 06:45")
    }

    func testTaskItemDecodesSavedTasksWithoutPhotos() throws {
        let json = """
        {
          "id": "38F0B10E-D3C8-4891-85B9-37DFB3A65CC6",
          "title": "Legacy reminder",
          "startSeconds": 32400,
          "endSeconds": 36000,
          "repeatDays": [],
          "createdAt": 1
        }
        """

        let task = try JSONDecoder().decode(TaskItem.self, from: Data(json.utf8))
        XCTAssertNil(task.imageFilename)
        XCTAssertNil(task.timeBlock)
    }

    func testTaskPhotoIsPersistedAndRemovedWithTask() throws {
        let suiteName = "TaskPhotoTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReminderPhotoTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let sourceURL = temporaryDirectory.appendingPathComponent("source.png")
        try makeTestImageData().write(to: sourceURL)

        let managedDirectory = temporaryDirectory.appendingPathComponent("Managed", isDirectory: true)
        let imageStore = TaskImageStore(directoryURL: managedDirectory)
        let filename = try imageStore.importImage(from: sourceURL)
        let managedURL = try XCTUnwrap(imageStore.fileURL(named: filename))

        XCTAssertTrue(FileManager.default.fileExists(atPath: managedURL.path))
        XCTAssertNotNil(imageStore.image(named: filename))

        let store = TaskStore(defaults: defaults, storageKey: "photoTasks", imageStore: imageStore)
        store.addTask(
            title: "Photo reminder",
            start: date(year: 2026, month: 8, day: 26, hour: 9),
            end: date(year: 2026, month: 8, day: 26, hour: 10),
            repeatDays: [],
            imageFilename: filename
        )

        let reloadedStore = TaskStore(defaults: defaults, storageKey: "photoTasks", imageStore: imageStore)
        let savedTask = try XCTUnwrap(reloadedStore.tasks.first)
        XCTAssertEqual(savedTask.imageFilename, filename)

        reloadedStore.deleteTask(savedTask)
        XCTAssertFalse(FileManager.default.fileExists(atPath: managedURL.path))
        XCTAssertNil(imageStore.image(named: filename))
    }

    func testTaskCanBeEditedAndItsPhotoReplacedOrRemoved() throws {
        let suiteName = "TaskEditTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReminderEditTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let sourceURL = temporaryDirectory.appendingPathComponent("source.png")
        try makeTestImageData().write(to: sourceURL)

        let managedDirectory = temporaryDirectory.appendingPathComponent("Managed", isDirectory: true)
        let imageStore = TaskImageStore(directoryURL: managedDirectory)
        let originalFilename = try imageStore.importImage(from: sourceURL)
        let replacementFilename = try imageStore.importImage(from: sourceURL)
        let originalURL = try XCTUnwrap(imageStore.fileURL(named: originalFilename))
        let replacementURL = try XCTUnwrap(imageStore.fileURL(named: replacementFilename))
        let store = TaskStore(defaults: defaults, storageKey: "editableTasks", imageStore: imageStore)

        XCTAssertTrue(store.addTask(
            title: "Original",
            start: date(year: 2026, month: 8, day: 27, hour: 9),
            end: date(year: 2026, month: 8, day: 27, hour: 10),
            repeatDays: [],
            imageFilename: originalFilename
        ))
        let originalTask = try XCTUnwrap(store.tasks.first)

        XCTAssertTrue(store.updateTask(
            originalTask,
            title: "Updated",
            start: date(year: 2026, month: 8, day: 27, hour: 11, minute: 15),
            end: date(year: 2026, month: 8, day: 27, hour: 12, minute: 45),
            repeatDays: [Weekday.monday.rawValue, Weekday.wednesday.rawValue],
            imageFilename: replacementFilename
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: replacementURL.path))

        let reloadedStore = TaskStore(defaults: defaults, storageKey: "editableTasks", imageStore: imageStore)
        let updatedTask = try XCTUnwrap(reloadedStore.tasks.first)
        XCTAssertEqual(updatedTask.id, originalTask.id)
        XCTAssertEqual(updatedTask.createdAt, originalTask.createdAt)
        XCTAssertEqual(updatedTask.title, "Updated")
        XCTAssertEqual(updatedTask.startSeconds, 11 * 3_600 + 15 * 60)
        XCTAssertEqual(updatedTask.endSeconds, 12 * 3_600 + 45 * 60)
        XCTAssertEqual(updatedTask.repeatDays, [Weekday.monday.rawValue, Weekday.wednesday.rawValue])
        XCTAssertEqual(updatedTask.imageFilename, replacementFilename)

        XCTAssertTrue(reloadedStore.updateTask(
            updatedTask,
            title: updatedTask.title,
            start: date(year: 2026, month: 8, day: 27, hour: 11, minute: 15),
            end: date(year: 2026, month: 8, day: 27, hour: 12, minute: 45),
            repeatDays: Set(updatedTask.repeatDays),
            imageFilename: nil
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: replacementURL.path))
    }

    func testDisplayProtectionMovesContentWithinSafeBounds() {
        let canvas = CGSize(width: 1_440, height: 900)
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let first = DisplayProtection.offset(at: start, canvasSize: canvas)
        let later = DisplayProtection.offset(
            at: start.addingTimeInterval(60),
            canvasSize: canvas
        )

        XCTAssertNotEqual(first, later)
        XCTAssertLessThanOrEqual(abs(later.width), 96)
        XCTAssertLessThanOrEqual(abs(later.height), 54)

        let edgeOffset = DisplayProtection.offset(
            at: laterDate(start, seconds: 120),
            canvasSize: canvas,
            seed: 42,
            edgeAnchored: true
        )
        XCTAssertGreaterThanOrEqual(edgeOffset.width, 0)
        XCTAssertLessThanOrEqual(edgeOffset.width, 96)
        XCTAssertLessThanOrEqual(edgeOffset.height, 0)
        XCTAssertGreaterThanOrEqual(edgeOffset.height, -54)

        let reducedFirst = DisplayProtection.offset(
            at: start,
            canvasSize: canvas,
            reduceMotion: true
        )
        let reducedLater = DisplayProtection.offset(
            at: start.addingTimeInterval(300),
            canvasSize: canvas,
            reduceMotion: true
        )
        XCTAssertNotEqual(reducedFirst, reducedLater)
    }

    private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }

    private func laterDate(_ date: Date, seconds: TimeInterval) -> Date {
        date.addingTimeInterval(seconds)
    }

    private func makeTestImageData() throws -> Data {
        let image = NSImage(size: NSSize(width: 120, height: 80))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 120, height: 80).fill()
        image.unlockFocus()

        let tiffData = try XCTUnwrap(image.tiffRepresentation)
        let representation = try XCTUnwrap(NSBitmapImageRep(data: tiffData))
        return try XCTUnwrap(representation.representation(using: .png, properties: [:]))
    }
}
