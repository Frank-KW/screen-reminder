import SwiftUI

@main
struct ReminderApp: App {
    @StateObject private var timeBlockSettings = TimeBlockSettings()
    @StateObject private var worldClockStore = WorldClockStore()

    init() {
        LegacyDataMigration.run()
    }

    var body: some Scene {
        WindowGroup("Screen Reminder") {
            ContentView()
                .environmentObject(timeBlockSettings)
                .environmentObject(worldClockStore)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1080, height: 720)

        Settings {
            TimeBlockSettingsView()
                .environmentObject(timeBlockSettings)
        }
    }
}
