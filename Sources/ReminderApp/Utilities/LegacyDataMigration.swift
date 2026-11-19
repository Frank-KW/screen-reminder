import Foundation

/// The app used to be "com.example.Reminder". On the first launch under the new ID,
/// copy the saved tasks, time blocks and city clocks across once.
/// Photos live in Application Support/Reminder and do not depend on the ID.
enum LegacyDataMigration {
    static let legacyDomain = "com.example.Reminder"
    static let migratedKeys = ["tasks", "timeBlockSettings", "worldClocks"]
    static let doneKey = "didMigrateLegacyData"

    static func run(
        into defaults: UserDefaults = .standard,
        legacyValues: [String: Any]? = UserDefaults.standard.persistentDomain(forName: legacyDomain)
    ) {
        guard !defaults.bool(forKey: doneKey) else { return }
        defer { defaults.set(true, forKey: doneKey) }

        guard let legacyValues else { return }
        for key in migratedKeys where defaults.object(forKey: key) == nil {
            if let value = legacyValues[key] {
                defaults.set(value, forKey: key)
            }
        }
    }
}
