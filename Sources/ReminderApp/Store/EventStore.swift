import Combine
import Foundation

final class EventStore: ObservableObject {
    @Published private(set) var events: [EventItem] = []
    @Published private(set) var storageWarning: String?
    /// Alerts the app shows itself, only when macOS notifications are off.
    @Published var inAppAlerts: [PlannedAlert] = []

    private let defaults: UserDefaults
    private let storageKey: String
    private let notifier: EventNotifying?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var lastAlertCheck: Date
    private var timer: Timer?

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "events",
        notifier: EventNotifying? = EventNotifier.shared,
        now: Date = Date(),
        runsTimer: Bool = true
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.notifier = notifier
        self.lastAlertCheck = now
        load()
        rescheduleNotifications(now: now)
        if runsTimer {
            let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
                self?.checkInAppAlerts()
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: Lists

    func upcoming(at now: Date = Date()) -> [EventItem] {
        events.filter { !$0.hasEnded(at: now) }
    }

    func past(at now: Date = Date()) -> [EventItem] {
        events.filter { $0.hasEnded(at: now) }.reversed()
    }

    func event(withID id: UUID) -> EventItem? {
        events.first { $0.id == id }
    }

    // MARK: Changes

    @discardableResult
    func add(title: String, start: Date, end: Date, alertMinutes: [Int], notes: String) -> Bool {
        let event = EventItem(
            title: Self.cleanTitle(title),
            startDate: start,
            endDate: end,
            alertMinutes: alertMinutes,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        return commit(events + [event], asksPermission: !event.alertMinutes.isEmpty)
    }

    @discardableResult
    func update(_ id: UUID, title: String, start: Date, end: Date, alertMinutes: [Int], notes: String) -> Bool {
        guard let index = events.firstIndex(where: { $0.id == id }) else {
            storageWarning = "That event is no longer in your list."
            return false
        }
        var next = events
        next[index] = EventItem(
            id: id,
            title: Self.cleanTitle(title),
            startDate: start,
            endDate: end,
            alertMinutes: alertMinutes,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: events[index].createdAt
        )
        return commit(next, asksPermission: !next[index].alertMinutes.isEmpty)
    }

    func delete(_ id: UUID) {
        commit(events.filter { $0.id != id }, asksPermission: false)
    }

    /// Used by restore: throws away the current events and keeps these.
    @discardableResult
    func replaceAll(with newEvents: [EventItem]) -> Bool {
        let cleaned = newEvents.map {
            EventItem(
                id: $0.id,
                title: Self.cleanTitle($0.title),
                startDate: $0.startDate,
                endDate: $0.endDate,
                alertMinutes: $0.alertMinutes,
                notes: $0.notes,
                createdAt: $0.createdAt
            )
        }
        return commit(cleaned, asksPermission: cleaned.contains { !$0.alertMinutes.isEmpty })
    }

    static func cleanTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let short = String(trimmed.prefix(EventItem.maxTitleLength))
        return short.isEmpty ? "Untitled event" : short
    }

    // MARK: Alerts

    /// Shows alerts that came due since the last check, if macOS will not show them.
    func checkInAppAlerts(now: Date = Date()) {
        defer { lastAlertCheck = now }
        guard notifier?.canDeliver != true else { return }
        let due = EventAlertPlanner.alertsDue(for: events, after: lastAlertCheck, upTo: now)
        if !due.isEmpty {
            inAppAlerts.append(contentsOf: due)
        }
    }

    func dismissInAppAlert() {
        if !inAppAlerts.isEmpty {
            inAppAlerts.removeFirst()
        }
    }

    private func rescheduleNotifications(now: Date = Date()) {
        notifier?.reschedule(EventAlertPlanner.upcomingAlerts(for: events, after: now))
    }

    // MARK: Storage

    @discardableResult
    private func commit(_ next: [EventItem], asksPermission: Bool) -> Bool {
        let sorted = next.sorted {
            $0.startDate != $1.startDate ? $0.startDate < $1.startDate : $0.createdAt < $1.createdAt
        }
        do {
            defaults.set(try encoder.encode(sorted), forKey: storageKey)
        } catch {
            storageWarning = "Events could not be saved. Your previous saved list was left unchanged."
            return false
        }
        events = sorted
        storageWarning = nil
        if asksPermission {
            notifier?.requestPermission()
        }
        rescheduleNotifications()
        return true
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey) else { return }
        do {
            events = try decoder.decode([EventItem].self, from: data)
                .sorted { $0.startDate < $1.startDate }
        } catch {
            storageWarning = "Saved events could not be read. New events will still be saved."
        }
    }
}
