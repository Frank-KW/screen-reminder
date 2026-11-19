import SwiftUI

@main
struct ReminderApp: App {
    @StateObject private var timeBlockSettings: TimeBlockSettings
    @StateObject private var worldClockStore: WorldClockStore
    @StateObject private var taskStore: TaskStore
    @StateObject private var eventStore: EventStore

    init() {
        // Must run before the stores read their saved data.
        LegacyDataMigration.run()
        _timeBlockSettings = StateObject(wrappedValue: TimeBlockSettings())
        _worldClockStore = StateObject(wrappedValue: WorldClockStore())
        _taskStore = StateObject(wrappedValue: TaskStore())
        _eventStore = StateObject(wrappedValue: EventStore())
    }

    private var backupService: BackupService {
        BackupService(
            events: eventStore,
            tasks: taskStore,
            timeBlocks: timeBlockSettings,
            worldClocks: worldClockStore,
            images: .shared
        )
    }

    var body: some Scene {
        WindowGroup("Screen Reminder") {
            ContentView(
                onExport: { BackupController.export(using: backupService) },
                onRestore: { BackupController.restore(using: backupService) }
            )
            .environmentObject(timeBlockSettings)
            .environmentObject(worldClockStore)
            .environmentObject(taskStore)
            .environmentObject(eventStore)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1080, height: 720)
        .commands {
            CommandGroup(after: .importExport) {
                Button("Export Backup…") { BackupController.export(using: backupService) }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                Button("Restore from Backup…") { BackupController.restore(using: backupService) }
                    .keyboardShortcut("b", modifiers: [.command, .shift, .option])
            }
        }

        Settings {
            TimeBlockSettingsView()
                .environmentObject(timeBlockSettings)
        }
    }
}
