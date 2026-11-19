import Foundation
import Combine
import AppKit

final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [TaskItem] = []
    @Published private(set) var storageWarning: String?

    private let defaults: UserDefaults
    private let storageKey: String
    private let imageStore: TaskImageStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "tasks",
        imageStore: TaskImageStore = .shared
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.imageStore = imageStore
        load()
    }

    @discardableResult
    func addTask(
        title: String,
        start: Date,
        end: Date,
        repeatDays: Set<Int>,
        imageFilename: String? = nil,
        timeBlock: TimeBlock? = nil
    ) -> Bool {
        let previousTasks = tasks
        let startSeconds = TimeUtils.secondsSinceMidnight(for: start)
        let endSeconds = TimeUtils.secondsSinceMidnight(for: end)
        let normalizedDays = repeatDays.sorted()
        let newTask = TaskItem(
            title: title,
            startSeconds: startSeconds,
            endSeconds: endSeconds,
            repeatDays: normalizedDays,
            imageFilename: imageFilename,
            timeBlock: timeBlock
        )
        tasks.append(newTask)
        sortTasks()
        guard save() else {
            tasks = previousTasks
            return false
        }
        return true
    }

    @discardableResult
    func updateTask(
        _ task: TaskItem,
        title: String,
        start: Date,
        end: Date,
        repeatDays: Set<Int>,
        imageFilename: String?,
        timeBlock: TimeBlock? = nil
    ) -> Bool {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else {
            storageWarning = "That reminder is no longer in your schedule."
            return false
        }

        let previousTasks = tasks
        let previousImageFilename = tasks[index].imageFilename
        tasks[index].title = title
        tasks[index].startSeconds = TimeUtils.secondsSinceMidnight(for: start)
        tasks[index].endSeconds = TimeUtils.secondsSinceMidnight(for: end)
        tasks[index].repeatDays = repeatDays.sorted()
        tasks[index].imageFilename = imageFilename
        tasks[index].timeBlock = timeBlock
        sortTasks()

        guard save() else {
            tasks = previousTasks
            return false
        }

        if previousImageFilename != imageFilename, let previousImageFilename {
            do {
                try imageStore.removeImage(named: previousImageFilename)
            } catch {
                storageWarning = "The reminder was updated, but its old photo could not be removed."
            }
        }
        return true
    }

    func deleteTask(_ task: TaskItem) {
        tasks.removeAll { $0.id == task.id }
        let didSave = save()
        if didSave, let imageFilename = task.imageFilename {
            do {
                try imageStore.removeImage(named: imageFilename)
            } catch {
                storageWarning = "The reminder was deleted, but its photo could not be removed."
            }
        }
    }

    /// Used by restore: throws away the current reminders and keeps these.
    /// Old photo files stay on disk, so a safety backup can still bring them back.
    @discardableResult
    func replaceAll(with newTasks: [TaskItem]) -> Bool {
        let previousTasks = tasks
        tasks = newTasks
        sortTasks()
        guard save() else {
            tasks = previousTasks
            return false
        }
        return true
    }

    func image(for task: TaskItem) -> NSImage? {
        guard let filename = task.imageFilename else { return nil }
        return imageStore.image(named: filename)
    }

    func importImage(from sourceURL: URL) throws -> String {
        try imageStore.importImage(from: sourceURL)
    }

    func discardImage(named filename: String) {
        try? imageStore.removeImage(named: filename)
    }

    func activeTask(at date: Date = Date()) -> TaskItem? {
        let nowSeconds = TimeUtils.secondsSinceMidnight(for: date)
        var bestTask: TaskItem?
        var shortestElapsed = Int.max

        for task in tasks where task.isActive(at: date) {
            let elapsed = TimeUtils.elapsedSinceStart(
                startSeconds: task.startSeconds,
                nowSeconds: nowSeconds
            )
            if elapsed < shortestElapsed || (elapsed == shortestElapsed && task.createdAt > (bestTask?.createdAt ?? 0)) {
                bestTask = task
                shortestElapsed = elapsed
            }
        }
        return bestTask
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey) else {
            tasks = []
            return
        }
        do {
            tasks = try decoder.decode([TaskItem].self, from: data)
            sortTasks()
            storageWarning = nil
        } catch {
            tasks = []
            storageWarning = "Saved tasks could not be read. New tasks will still be saved."
        }
    }

    @discardableResult
    private func save() -> Bool {
        do {
            let data = try encoder.encode(tasks)
            defaults.set(data, forKey: storageKey)
            storageWarning = nil
            return true
        } catch {
            storageWarning = "Tasks could not be saved. Your previous saved list was left unchanged."
            return false
        }
    }

    private func sortTasks() {
        tasks.sort {
            if $0.startSeconds != $1.startSeconds {
                return $0.startSeconds < $1.startSeconds
            }
            return $0.createdAt < $1.createdAt
        }
    }
}
