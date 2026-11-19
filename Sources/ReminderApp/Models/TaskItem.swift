import Foundation

struct TaskItem: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var startSeconds: Int
    var endSeconds: Int
    var repeatDays: [Int]
    var createdAt: TimeInterval
    var imageFilename: String?
    var timeBlock: TimeBlock?

    init(
        id: UUID = UUID(),
        title: String,
        startSeconds: Int,
        endSeconds: Int,
        repeatDays: [Int] = [],
        createdAt: TimeInterval = Date().timeIntervalSince1970,
        imageFilename: String? = nil,
        timeBlock: TimeBlock? = nil
    ) {
        self.id = id
        self.title = title
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.repeatDays = repeatDays
        self.createdAt = createdAt
        self.imageFilename = imageFilename
        self.timeBlock = timeBlock
    }

    var timeRangeText: String {
        if startSeconds == endSeconds {
            return "All day"
        }
        return "\(TimeUtils.timeString(from: startSeconds)) → \(TimeUtils.timeString(from: endSeconds))"
    }

    var scheduleTimeText: String {
        guard let timeBlock else { return timeRangeText }
        return "\(timeBlock.displayName) · \(timeRangeText)"
    }

    func isActive(at date: Date = Date()) -> Bool {
        TimeUtils.matchesSchedule(
            startSeconds: startSeconds,
            endSeconds: endSeconds,
            repeatDays: repeatDays,
            at: date
        )
    }

    var repeatSummary: String {
        let selected = Set(repeatDays)
        if selected.isEmpty || selected.count == 7 {
            return "Every day"
        }
        if selected == Weekday.weekdaySet {
            return "Weekdays"
        }
        if selected == Weekday.weekendSet {
            return "Weekends"
        }
        let labels = Weekday.ordered.compactMap { selected.contains($0.rawValue) ? $0.shortLabel : nil }
        return labels.isEmpty ? "Custom" : labels.joined(separator: " ")
    }
}
