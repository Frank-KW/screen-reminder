import Foundation

enum TimeBlock: String, CaseIterable, Codable, Identifiable, Hashable {
    case earlyMorning
    case morningWorkBlock
    case lunchBreak
    case afternoonWorkBlock
    case wrapUp
    case afterWork
    case windDown
    case sleep
    case workingHours

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .earlyMorning: return "Early Morning"
        case .morningWorkBlock: return "Morning Work Block"
        case .lunchBreak: return "Lunch Break"
        case .afternoonWorkBlock: return "Afternoon Work Block"
        case .wrapUp: return "Wrap-up"
        case .afterWork: return "After Work"
        case .windDown: return "Wind-down"
        case .sleep: return "Sleep"
        case .workingHours: return "Working Hours"
        }
    }

    var symbolName: String {
        switch self {
        case .earlyMorning: return "sunrise.fill"
        case .morningWorkBlock: return "briefcase.fill"
        case .lunchBreak: return "fork.knife"
        case .afternoonWorkBlock: return "sun.max.fill"
        case .wrapUp: return "checklist"
        case .afterWork: return "house.fill"
        case .windDown: return "moon.haze.fill"
        case .sleep: return "bed.double.fill"
        case .workingHours: return "clock.badge.checkmark.fill"
        }
    }

    static let ukDefaultRanges: [TimeBlock: TimeBlockRange] = [
        .earlyMorning: TimeBlockRange(startHour: 6, endHour: 9),
        .morningWorkBlock: TimeBlockRange(startHour: 9, endHour: 12),
        .lunchBreak: TimeBlockRange(startHour: 12, endHour: 13),
        .afternoonWorkBlock: TimeBlockRange(startHour: 13, endHour: 17),
        .wrapUp: TimeBlockRange(startHour: 17, endHour: 17, endMinute: 30),
        .afterWork: TimeBlockRange(startHour: 17, startMinute: 30, endHour: 20),
        .windDown: TimeBlockRange(startHour: 20, endHour: 22, endMinute: 30),
        .sleep: TimeBlockRange(startHour: 22, startMinute: 30, endHour: 6),
        .workingHours: TimeBlockRange(startHour: 9, endHour: 17, endMinute: 30)
    ]
}

struct TimeBlockRange: Codable, Equatable {
    var startSeconds: Int
    var endSeconds: Int

    init(startSeconds: Int, endSeconds: Int) {
        self.startSeconds = Self.clamp(startSeconds)
        self.endSeconds = Self.clamp(endSeconds)
    }

    init(startHour: Int, startMinute: Int = 0, endHour: Int, endMinute: Int = 0) {
        self.init(
            startSeconds: startHour * 3_600 + startMinute * 60,
            endSeconds: endHour * 3_600 + endMinute * 60
        )
    }

    var timeRangeText: String {
        if startSeconds == endSeconds {
            return "All day"
        }
        return "\(TimeUtils.timeString(from: startSeconds)) → \(TimeUtils.timeString(from: endSeconds))"
    }

    var normalized: TimeBlockRange {
        TimeBlockRange(startSeconds: startSeconds, endSeconds: endSeconds)
    }

    private static func clamp(_ seconds: Int) -> Int {
        min(max(0, seconds), TimeUtils.secondsPerDay - 1)
    }
}
