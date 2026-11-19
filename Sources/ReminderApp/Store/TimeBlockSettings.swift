import Combine
import Foundation

final class TimeBlockSettings: ObservableObject {
    @Published private(set) var ranges: [TimeBlock: TimeBlockRange]

    private let defaults: UserDefaults
    private let storageKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private struct StoredSettings: Codable {
        var ranges: [String: TimeBlockRange]
    }

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "timeBlockSettings"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.ranges = TimeBlock.ukDefaultRanges
        load()
    }

    func range(for block: TimeBlock) -> TimeBlockRange {
        ranges[block] ?? TimeBlock.ukDefaultRanges[block]!
    }

    func update(_ range: TimeBlockRange, for block: TimeBlock) {
        ranges[block] = range.normalized
        save()
    }

    func matchingBlock(startSeconds: Int, endSeconds: Int) -> TimeBlock? {
        TimeBlock.allCases.first {
            let range = range(for: $0)
            return range.startSeconds == startSeconds && range.endSeconds == endSeconds
        }
    }

    /// Used by restore. Blocks missing from the backup keep their UK default.
    func replaceAll(with stored: [String: TimeBlockRange]) {
        var merged = TimeBlock.ukDefaultRanges
        for block in TimeBlock.allCases {
            if let range = stored[block.rawValue] {
                merged[block] = range.normalized
            }
        }
        ranges = merged
        save()
    }

    /// The ranges keyed by name, the shape used on disk and in backups.
    var storedRanges: [String: TimeBlockRange] {
        Dictionary(uniqueKeysWithValues: ranges.map { ($0.key.rawValue, $0.value.normalized) })
    }

    func restoreUKDefaults() {
        ranges = TimeBlock.ukDefaultRanges
        save()
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let stored = try? decoder.decode(StoredSettings.self, from: data) else {
            return
        }

        var merged = TimeBlock.ukDefaultRanges
        for block in TimeBlock.allCases {
            if let range = stored.ranges[block.rawValue] {
                merged[block] = range.normalized
            }
        }
        ranges = merged
    }

    private func save() {
        let stored = StoredSettings(ranges: storedRanges)
        guard let data = try? encoder.encode(stored) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
