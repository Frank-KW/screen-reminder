import Foundation

/// One city clock shown on the full-screen display.
struct WorldClock: Identifiable, Codable, Equatable {
    let id: UUID
    var cityName: String
    var timeZoneID: String

    init(id: UUID = UUID(), cityName: String, timeZoneID: String) {
        self.id = id
        self.cityName = cityName
        self.timeZoneID = timeZoneID
    }

    var timeZone: TimeZone? {
        TimeZone(identifier: timeZoneID)
    }
}

/// A city the user can pick, mapped to the time zone it uses.
struct CitySuggestion: Identifiable, Equatable, Hashable {
    let name: String
    let timeZoneID: String

    var id: String { "\(name)|\(timeZoneID)" }

    /// "Asia/Hong_Kong" -> "Asia", "America/Argentina/Buenos_Aires" -> "America · Argentina".
    var regionText: String {
        let parts = timeZoneID.split(separator: "/").dropLast()
        return parts.map { $0.replacingOccurrences(of: "_", with: " ") }.joined(separator: " · ")
    }
}

enum WorldClockMath {
    struct HandAngles: Equatable {
        var hour: Double
        var minute: Double
        var second: Double
    }

    /// Well-known cities that are not named in the system's time zone list.
    static let cityAliases: [String: String] = [
        "Abu Dhabi": "Asia/Dubai",
        "Atlanta": "America/New_York",
        "Austin": "America/Chicago",
        "Bangalore": "Asia/Kolkata",
        "Barcelona": "Europe/Madrid",
        "Beijing": "Asia/Shanghai",
        "Bengaluru": "Asia/Kolkata",
        "Boston": "America/New_York",
        "Cambridge": "Europe/London",
        "Chennai": "Asia/Kolkata",
        "Dallas": "America/Chicago",
        "Edinburgh": "Europe/London",
        "Frankfurt": "Europe/Berlin",
        "Geneva": "Europe/Zurich",
        "Guangzhou": "Asia/Shanghai",
        "Hanoi": "Asia/Ho_Chi_Minh",
        "Houston": "America/Chicago",
        "Kyoto": "Asia/Tokyo",
        "Las Vegas": "America/Los_Angeles",
        "Manchester": "Europe/London",
        "Miami": "America/New_York",
        "Milan": "Europe/Rome",
        "Mumbai": "Asia/Kolkata",
        "Munich": "Europe/Berlin",
        "New Delhi": "Asia/Kolkata",
        "Osaka": "Asia/Tokyo",
        "Oxford": "Europe/London",
        "Philadelphia": "America/New_York",
        "Rio de Janeiro": "America/Sao_Paulo",
        "San Diego": "America/Los_Angeles",
        "San Francisco": "America/Los_Angeles",
        "Seattle": "America/Los_Angeles",
        "Shenzhen": "Asia/Shanghai",
        "Washington, D.C.": "America/New_York",
        "Wellington": "Pacific/Auckland"
    ]

    /// "America/New_York" -> "New York".
    static func cityName(fromIdentifier identifier: String) -> String {
        let last = identifier.split(separator: "/").last.map(String.init) ?? identifier
        return last.replacingOccurrences(of: "_", with: " ")
    }

    /// Every pickable city: real time zone cities plus the aliases, sorted by name.
    static func allSuggestions(
        timeZoneIDs: [String] = TimeZone.knownTimeZoneIdentifiers
    ) -> [CitySuggestion] {
        let zoneCities = timeZoneIDs
            .filter { $0.contains("/") }
            .map { CitySuggestion(name: cityName(fromIdentifier: $0), timeZoneID: $0) }
        let aliases = cityAliases
            .filter { TimeZone(identifier: $0.value) != nil }
            .map { CitySuggestion(name: $0.key, timeZoneID: $0.value) }
        return (zoneCities + aliases).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Cities whose name or time zone matches the query. Names that start with it come first.
    static func search(_ query: String, in suggestions: [CitySuggestion]) -> [CitySuggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return suggestions }

        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let underscored = trimmed.replacingOccurrences(of: " ", with: "_")
        let matches = suggestions.filter {
            $0.name.range(of: trimmed, options: options) != nil
                || $0.timeZoneID.range(of: trimmed, options: options) != nil
                || $0.timeZoneID.range(of: underscored, options: options) != nil
        }
        let prefix = matches.filter { $0.name.range(of: trimmed, options: options.union(.anchored)) != nil }
        let rest = matches.filter { $0.name.range(of: trimmed, options: options.union(.anchored)) == nil }
        return prefix + rest
    }

    static func offsetSeconds(
        of timeZone: TimeZone,
        at date: Date,
        relativeTo local: TimeZone = .current
    ) -> Int {
        timeZone.secondsFromGMT(for: date) - local.secondsFromGMT(for: date)
    }

    /// 28800 -> "+8 hrs", 19800 -> "+5:30 hrs", 3600 -> "+1 hr", 0 -> "+0 hrs".
    static func offsetText(seconds: Int) -> String {
        let sign = seconds < 0 ? "-" : "+"
        let total = abs(seconds)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        if minutes == 0 {
            return "\(sign)\(hours) \(hours == 1 ? "hr" : "hrs")"
        }
        return "\(sign)\(hours):\(String(format: "%02d", minutes)) hrs"
    }

    /// How many calendar days the city is ahead of (positive) or behind (negative) the local day.
    static func dayOffset(
        of timeZone: TimeZone,
        at date: Date,
        relativeTo local: TimeZone = .current
    ) -> Int {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!

        func dayStart(in zone: TimeZone) -> Date? {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return utc.date(from: parts)
        }

        guard let there = dayStart(in: timeZone), let here = dayStart(in: local) else { return 0 }
        return utc.dateComponents([.day], from: here, to: there).day ?? 0
    }

    static func dayText(forOffset offset: Int) -> String {
        switch offset {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        default: return offset > 0 ? "+\(offset) days" : "\(offset) days"
        }
    }

    /// "Tomorrow, +8 hrs" — the same line the Mac and iPhone world clock widgets show.
    static func relativeText(
        for timeZone: TimeZone,
        at date: Date,
        relativeTo local: TimeZone = .current
    ) -> String {
        let day = dayText(forOffset: dayOffset(of: timeZone, at: date, relativeTo: local))
        let offset = offsetText(seconds: offsetSeconds(of: timeZone, at: date, relativeTo: local))
        return "\(day), \(offset)"
    }

    static func timeText(in timeZone: TimeZone, at date: Date) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = timeZone
        return date.formatted(style)
    }

    /// Hand angles in degrees, clockwise from 12 o'clock.
    static func handAngles(in timeZone: TimeZone, at date: Date) -> HandAngles {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        let hour = Double((parts.hour ?? 0) % 12)
        let minute = Double(parts.minute ?? 0)
        let second = Double(parts.second ?? 0)
        return HandAngles(
            hour: (hour + minute / 60) * 30,
            minute: (minute + second / 60) * 6,
            second: second * 6
        )
    }

    /// Daytime (6 AM to 6 PM) gets a white face, night a dark one, like the system widget.
    static func isDaytime(in timeZone: TimeZone, at date: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let hour = calendar.component(.hour, from: date)
        return (6..<18).contains(hour)
    }
}
