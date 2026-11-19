import Foundation

/// Everything the app saves, in one JSON file the user can keep and bring back.
struct BackupFile: Codable, Equatable {
    static let formatName = "ScreenReminderBackup"
    static let currentVersion = 1
    static let fileExtension = "json"

    var format: String = formatName
    var version: Int = currentVersion
    var exportedAt: Date
    var events: [EventItem]
    var tasks: [TaskItem]
    var timeBlocks: [String: TimeBlockRange]
    var worldClocks: [WorldClock]
    var showsWorldClocks: Bool
    /// Photo file name -> JPEG bytes (written as base64 text in the file).
    var photos: [String: Data]

    init(
        exportedAt: Date,
        events: [EventItem],
        tasks: [TaskItem] = [],
        timeBlocks: [String: TimeBlockRange] = [:],
        worldClocks: [WorldClock] = [],
        showsWorldClocks: Bool = true,
        photos: [String: Data] = [:]
    ) {
        self.exportedAt = exportedAt
        self.events = events
        self.tasks = tasks
        self.timeBlocks = timeBlocks
        self.worldClocks = worldClocks
        self.showsWorldClocks = showsWorldClocks
        self.photos = photos
    }

    private enum CodingKeys: String, CodingKey {
        case format, version, exportedAt, events, tasks, timeBlocks, worldClocks, showsWorldClocks, photos
    }

    /// Only `format`, `version` and `events` are required, so a file with just events still restores.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decode(String.self, forKey: .format)
        version = try c.decode(Int.self, forKey: .version)
        guard format == Self.formatName else { throw BackupError.notABackup }
        guard version <= Self.currentVersion else { throw BackupError.newerVersion(version) }
        exportedAt = try c.decodeIfPresent(Date.self, forKey: .exportedAt) ?? Date(timeIntervalSince1970: 0)
        events = try c.decode([EventItem].self, forKey: .events)
        tasks = try c.decodeIfPresent([TaskItem].self, forKey: .tasks) ?? []
        timeBlocks = try c.decodeIfPresent([String: TimeBlockRange].self, forKey: .timeBlocks) ?? [:]
        worldClocks = try c.decodeIfPresent([WorldClock].self, forKey: .worldClocks) ?? []
        showsWorldClocks = try c.decodeIfPresent(Bool.self, forKey: .showsWorldClocks) ?? true
        photos = try c.decodeIfPresent([String: Data].self, forKey: .photos) ?? [:]
    }

    var summary: String {
        func count(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
        return [
            count(events.count, "event"),
            count(tasks.count, "reminder"),
            count(worldClocks.count, "world clock"),
            count(photos.count, "photo")
        ].joined(separator: ", ")
    }
}

enum BackupError: LocalizedError, Equatable {
    case notABackup
    case newerVersion(Int)
    case unreadable(String)
    case couldNotSave(String)

    var errorDescription: String? {
        switch self {
        case .notABackup:
            return "This file is not a Screen Reminder backup."
        case .newerVersion(let version):
            return "This backup was made by a newer Screen Reminder (format \(version)). Update the app, then try again."
        case .unreadable(let detail):
            return "The backup could not be read: \(detail)"
        case .couldNotSave(let what):
            return "\(what) could not be saved. Nothing else was changed after that point."
        }
    }
}

enum BackupCodec {
    static func encode(_ file: BackupFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(file)
    }

    static func decode(_ data: Data) throws -> BackupFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(BackupFile.self, from: data)
        } catch let error as BackupError {
            throw error
        } catch DecodingError.keyNotFound(let key, _) where key.stringValue == "format" {
            throw BackupError.notABackup
        } catch DecodingError.dataCorrupted {
            throw BackupError.unreadable("it is not valid JSON.")
        } catch {
            throw BackupError.unreadable(error.localizedDescription)
        }
    }

    /// "Screen Reminder Backup 2026-11-19 1430.json"
    static func suggestedFileName(at date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        return "Screen Reminder Backup \(formatter.string(from: date)).\(BackupFile.fileExtension)"
    }
}

enum RestoreScope {
    case everything
    case eventsOnly
}

struct RestoreResult: Equatable {
    var events = 0
    var tasks = 0
    var worldClocks = 0
    var photos = 0
    /// Photos the backup named but could not put back; their reminders keep no photo.
    var missingPhotos = 0
}

/// Builds backups from the live stores and writes them back on restore.
struct BackupService {
    let events: EventStore
    let tasks: TaskStore
    let timeBlocks: TimeBlockSettings
    let worldClocks: WorldClockStore
    let images: TaskImageStore

    func makeBackup(at now: Date = Date()) -> BackupFile {
        var photos: [String: Data] = [:]
        for name in Set(tasks.tasks.compactMap(\.imageFilename)) {
            if let data = images.imageData(named: name) {
                photos[name] = data
            }
        }
        return BackupFile(
            exportedAt: now,
            events: events.events,
            tasks: tasks.tasks,
            timeBlocks: timeBlocks.storedRanges,
            worldClocks: worldClocks.clocks,
            showsWorldClocks: worldClocks.showsInDisplay,
            photos: photos
        )
    }

    @discardableResult
    func restore(_ file: BackupFile, scope: RestoreScope) throws -> RestoreResult {
        var result = RestoreResult()

        guard events.replaceAll(with: file.events) else {
            throw BackupError.couldNotSave("The events")
        }
        result.events = file.events.count
        guard scope == .everything else { return result }

        var restoredTasks = file.tasks
        for index in restoredTasks.indices {
            guard let name = restoredTasks[index].imageFilename else { continue }
            if let data = file.photos[name], (try? images.restoreImage(data, named: name)) != nil {
                result.photos += 1
            } else if images.imageData(named: name) == nil {
                restoredTasks[index].imageFilename = nil
                result.missingPhotos += 1
            }
        }
        guard tasks.replaceAll(with: restoredTasks) else {
            throw BackupError.couldNotSave("The reminders")
        }
        result.tasks = restoredTasks.count

        timeBlocks.replaceAll(with: file.timeBlocks)
        worldClocks.replaceAll(with: file.worldClocks, showsInDisplay: file.showsWorldClocks)
        result.worldClocks = worldClocks.clocks.count
        return result
    }

    /// Saves what is here now before a restore replaces it, so a wrong restore can be undone.
    @discardableResult
    func writeSafetyCopy(into folder: URL, at now: Date = Date()) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Before restore — " + BackupCodec.suggestedFileName(at: now))
        try BackupCodec.encode(makeBackup(at: now)).write(to: url, options: .atomic)
        return url
    }

    static var safetyFolder: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support
            .appendingPathComponent("Reminder", isDirectory: true)
            .appendingPathComponent("Backups", isDirectory: true)
    }
}
