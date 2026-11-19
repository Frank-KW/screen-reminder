import Combine
import Foundation

final class WorldClockStore: ObservableObject {
    static let maxClocks = 8
    static let maxNameLength = 40

    @Published private(set) var clocks: [WorldClock] = []
    @Published private(set) var showsInDisplay = true

    private let defaults: UserDefaults
    private let storageKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private struct StoredClocks: Codable {
        var clocks: [WorldClock]
        var showsInDisplay: Bool
    }

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "worldClocks"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        load()
    }

    var canAddMore: Bool {
        clocks.count < Self.maxClocks
    }

    @discardableResult
    func add(cityName: String, timeZoneID: String) -> Bool {
        guard canAddMore, TimeZone(identifier: timeZoneID) != nil else { return false }
        clocks.append(WorldClock(
            cityName: Self.cleanName(cityName, timeZoneID: timeZoneID),
            timeZoneID: timeZoneID
        ))
        save()
        return true
    }

    @discardableResult
    func update(_ id: UUID, cityName: String, timeZoneID: String) -> Bool {
        guard let index = clocks.firstIndex(where: { $0.id == id }),
              TimeZone(identifier: timeZoneID) != nil else { return false }
        clocks[index].cityName = Self.cleanName(cityName, timeZoneID: timeZoneID)
        clocks[index].timeZoneID = timeZoneID
        save()
        return true
    }

    func delete(_ id: UUID) {
        clocks.removeAll { $0.id == id }
        save()
    }

    /// Moves a clock one place left (-1) or right (+1) in the display order.
    func move(_ id: UUID, by step: Int) {
        guard let index = clocks.firstIndex(where: { $0.id == id }) else { return }
        let target = index + step
        guard clocks.indices.contains(target) else { return }
        clocks.swapAt(index, target)
        save()
    }

    func setShowsInDisplay(_ value: Bool) {
        showsInDisplay = value
        save()
    }

    static func cleanName(_ name: String, timeZoneID: String) -> String {
        let collapsed = name
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        let trimmed = String(collapsed.prefix(maxNameLength))
        return trimmed.isEmpty ? WorldClockMath.cityName(fromIdentifier: timeZoneID) : trimmed
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let stored = try? decoder.decode(StoredClocks.self, from: data) else {
            return
        }
        clocks = Array(stored.clocks.filter { $0.timeZone != nil }.prefix(Self.maxClocks))
        showsInDisplay = stored.showsInDisplay
    }

    private func save() {
        let stored = StoredClocks(clocks: clocks, showsInDisplay: showsInDisplay)
        guard let data = try? encoder.encode(stored) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
