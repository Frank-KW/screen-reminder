import Foundation
import UserNotifications

/// Hands event alerts to macOS so they pop up even when the app is closed.
protocol EventNotifying: AnyObject {
    /// True when macOS will show our notifications. False means the app must show alerts itself.
    var canDeliver: Bool { get }
    func requestPermission()
    func reschedule(_ alerts: [PlannedAlert])
}

final class EventNotifier: NSObject, EventNotifying, UNUserNotificationCenterDelegate {
    static let shared = EventNotifier()
    static let identifierPrefix = "event-"

    /// Nil when the app runs without a bundle (for example `swift run`): macOS would crash us.
    private let center: UNUserNotificationCenter?
    private(set) var canDeliver = false

    override init() {
        center = Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
        super.init()
        center?.delegate = self
        refreshPermission()
    }

    func requestPermission() {
        center?.requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in
            self?.refreshPermission()
        }
    }

    private func refreshPermission() {
        center?.getNotificationSettings { [weak self] settings in
            let allowed = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
            DispatchQueue.main.async { self?.canDeliver = allowed }
        }
    }

    func reschedule(_ alerts: [PlannedAlert]) {
        guard let center else { return }
        center.getPendingNotificationRequests { requests in
            let old = requests.map(\.identifier).filter { $0.hasPrefix(Self.identifierPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: old)

            for alert in alerts {
                let content = UNMutableNotificationContent()
                content.title = alert.title
                content.body = alert.body
                content.sound = .default

                let parts = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second],
                    from: alert.fireDate
                )
                let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                center.add(UNNotificationRequest(identifier: alert.id, content: content, trigger: trigger))
            }
        }
    }

    /// Show the banner even while Screen Reminder is the front app.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
