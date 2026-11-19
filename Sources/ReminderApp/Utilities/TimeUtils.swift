import Foundation

enum TimeUtils {
    static let secondsPerDay = 24 * 60 * 60

    static func secondsSinceMidnight(for date: Date) -> Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let second = components.second ?? 0
        return hour * 3600 + minute * 60 + second
    }

    static func date(
        from secondsSinceMidnight: Int,
        on day: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        let clamped = min(max(0, secondsSinceMidnight), secondsPerDay - 1)
        return calendar.date(
            bySettingHour: clamped / 3_600,
            minute: (clamped % 3_600) / 60,
            second: clamped % 60,
            of: day
        ) ?? day
    }

    static func isActive(startSeconds: Int, endSeconds: Int, nowSeconds: Int) -> Bool {
        if startSeconds == endSeconds {
            return true
        }
        if startSeconds <= endSeconds {
            return nowSeconds >= startSeconds && nowSeconds <= endSeconds
        }
        return nowSeconds >= startSeconds || nowSeconds <= endSeconds
    }

    static func matchesSchedule(
        startSeconds: Int,
        endSeconds: Int,
        repeatDays: [Int],
        at date: Date
    ) -> Bool {
        let nowSeconds = secondsSinceMidnight(for: date)
        guard isActive(startSeconds: startSeconds, endSeconds: endSeconds, nowSeconds: nowSeconds) else {
            return false
        }

        let selectedDays = Set(repeatDays)
        guard !selectedDays.isEmpty, selectedDays.count < Weekday.allCases.count else {
            return true
        }

        var scheduledDay = weekdayIndex(for: date)
        if startSeconds > endSeconds, nowSeconds <= endSeconds {
            scheduledDay = scheduledDay == Weekday.sunday.rawValue
                ? Weekday.saturday.rawValue
                : scheduledDay - 1
        }
        return selectedDays.contains(scheduledDay)
    }

    static func elapsedSinceStart(startSeconds: Int, nowSeconds: Int) -> Int {
        if nowSeconds >= startSeconds {
            return nowSeconds - startSeconds
        }
        return secondsPerDay - startSeconds + nowSeconds
    }

    static func progress(startSeconds: Int, endSeconds: Int, nowSeconds: Int) -> Double {
        guard startSeconds != endSeconds else {
            return min(max(Double(nowSeconds) / Double(secondsPerDay), 0), 1)
        }

        let duration = endSeconds > startSeconds
            ? endSeconds - startSeconds
            : secondsPerDay - startSeconds + endSeconds
        let elapsed = elapsedSinceStart(startSeconds: startSeconds, nowSeconds: nowSeconds)
        return min(max(Double(elapsed) / Double(duration), 0), 1)
    }

    static func weekdayIndex(for date: Date) -> Int {
        Calendar.current.component(.weekday, from: date)
    }

    static func timeString(from seconds: Int) -> String {
        let clamped = min(max(0, seconds), secondsPerDay - 1)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        return String(format: "%02d:%02d", hours, minutes)
    }
}
