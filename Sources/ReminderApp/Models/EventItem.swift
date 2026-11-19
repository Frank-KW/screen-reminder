import Foundation

/// A one-off event on a real date, like a calendar entry, with alerts before it starts.
struct EventItem: Identifiable, Codable, Equatable {
    static let maxAlerts = 5
    static let maxAlertMinutes = 4 * 7 * 24 * 60
    static let maxTitleLength = 200

    let id: UUID
    var title: String
    var startDate: Date
    var endDate: Date
    /// Minutes before the start. 0 means "at the time of the event".
    var alertMinutes: [Int]
    var notes: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        startDate: Date,
        endDate: Date,
        alertMinutes: [Int] = [],
        notes: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        // Whole seconds only, so a backup file (which stores whole seconds) brings back the same value.
        let start = Self.wholeSeconds(startDate)
        self.startDate = start
        self.endDate = max(Self.wholeSeconds(endDate), start)
        self.alertMinutes = Self.cleanAlerts(alertMinutes)
        self.notes = notes
        self.createdAt = Self.wholeSeconds(createdAt)
    }

    private static func wholeSeconds(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }

    /// Sorted, no repeats, inside 0...4 weeks, at most 5 — the same limits Google Calendar uses.
    static func cleanAlerts(_ minutes: [Int]) -> [Int] {
        let valid = Set(minutes.filter { (0...maxAlertMinutes).contains($0) })
        return Array(valid.sorted().prefix(maxAlerts))
    }

    func alertDate(minutesBefore minutes: Int) -> Date {
        startDate.addingTimeInterval(TimeInterval(-minutes * 60))
    }

    func hasEnded(at now: Date) -> Bool {
        endDate < now
    }

    func isHappening(at now: Date) -> Bool {
        startDate <= now && now <= endDate
    }
}

enum EventFormat {
    /// The quick choices in the alert menu, like Google Calendar's list.
    static let presetAlertMinutes = [0, 5, 10, 15, 30, 60, 120, 24 * 60, 2 * 24 * 60, 7 * 24 * 60]

    enum Unit: Int, CaseIterable, Identifiable {
        case minutes = 1
        case hours = 60
        case days = 1_440
        case weeks = 10_080

        var id: Int { rawValue }

        func label(_ count: Int) -> String {
            switch self {
            case .minutes: return count == 1 ? "minute" : "minutes"
            case .hours: return count == 1 ? "hour" : "hours"
            case .days: return count == 1 ? "day" : "days"
            case .weeks: return count == 1 ? "week" : "weeks"
            }
        }

        var pluralLabel: String { label(2) }
    }

    /// 90 -> (90, minutes), 120 -> (2, hours), 1440 -> (1, day).
    static func split(_ minutes: Int) -> (count: Int, unit: Unit) {
        guard minutes > 0 else { return (0, .minutes) }
        for unit in [Unit.weeks, .days, .hours] where minutes % unit.rawValue == 0 {
            return (minutes / unit.rawValue, unit)
        }
        return (minutes, .minutes)
    }

    /// 0 -> "At time of event", 15 -> "15 minutes before", 1440 -> "1 day before".
    static func alertText(_ minutes: Int) -> String {
        guard minutes > 0 else { return "At time of event" }
        let parts = split(minutes)
        return "\(parts.count) \(parts.unit.label(parts.count)) before"
    }

    /// The line inside the notification: "Starts in 15 minutes · 14:00".
    static func alertBody(minutesBefore minutes: Int, start: Date, calendar: Calendar = .current) -> String {
        let time = timeText(start, calendar: calendar)
        guard minutes > 0 else { return "Starting now · \(time)" }
        let parts = split(minutes)
        return "Starts in \(parts.count) \(parts.unit.label(parts.count)) · \(time)"
    }

    static func timeText(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// "Thu 20 Nov 2026"
    static func dayText(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
    }

    /// "14:00 → 15:00", or "23:00 → 01:00 (+1 day)".
    static func timeRangeText(_ event: EventItem, calendar: Calendar = .current) -> String {
        let start = timeText(event.startDate, calendar: calendar)
        guard event.endDate > event.startDate else { return start }
        let end = timeText(event.endDate, calendar: calendar)
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: event.startDate),
            to: calendar.startOfDay(for: event.endDate)
        ).day ?? 0
        return days > 0 ? "\(start) → \(end) (+\(days) day\(days == 1 ? "" : "s"))" : "\(start) → \(end)"
    }

    /// Joins a calendar day with a clock time. Seconds are dropped.
    static func combine(day: Date, time: Date, calendar: Calendar = .current) -> Date {
        let dayParts = calendar.dateComponents([.year, .month, .day], from: day)
        let timeParts = calendar.dateComponents([.hour, .minute], from: time)
        var parts = DateComponents()
        parts.year = dayParts.year
        parts.month = dayParts.month
        parts.day = dayParts.day
        parts.hour = timeParts.hour
        parts.minute = timeParts.minute
        return calendar.date(from: parts) ?? day
    }

    /// The end on the start's day; if the end time is earlier than the start, it is the next day.
    static func endDate(start: Date, endTime: Date, calendar: Calendar = .current) -> Date {
        let sameDay = combine(day: start, time: endTime, calendar: calendar)
        if sameDay >= start { return sameDay }
        return calendar.date(byAdding: .day, value: 1, to: sameDay) ?? sameDay
    }
}

/// One alert that should go off at `fireDate`.
struct PlannedAlert: Identifiable, Equatable {
    let eventID: UUID
    let title: String
    let startDate: Date
    let minutesBefore: Int
    let fireDate: Date

    var id: String { "event-\(eventID.uuidString)-\(minutesBefore)" }

    var body: String {
        EventFormat.alertBody(minutesBefore: minutesBefore, start: startDate)
    }
}

enum EventAlertPlanner {
    /// macOS keeps at most 64 waiting notifications per app; stay under it.
    static let pendingLimit = 60

    /// Every alert still in the future, soonest first.
    static func upcomingAlerts(
        for events: [EventItem],
        after now: Date,
        limit: Int = pendingLimit
    ) -> [PlannedAlert] {
        let all = events.flatMap { event in
            event.alertMinutes.map { minutes in
                PlannedAlert(
                    eventID: event.id,
                    title: event.title,
                    startDate: event.startDate,
                    minutesBefore: minutes,
                    fireDate: event.alertDate(minutesBefore: minutes)
                )
            }
        }
        return Array(all.filter { $0.fireDate > now }.sorted { $0.fireDate < $1.fireDate }.prefix(limit))
    }

    /// Alerts that came due after `start` and up to `end`. Used when system notifications are off.
    static func alertsDue(for events: [EventItem], after start: Date, upTo end: Date) -> [PlannedAlert] {
        upcomingAlerts(for: events, after: start, limit: .max).filter { $0.fireDate <= end }
    }
}
