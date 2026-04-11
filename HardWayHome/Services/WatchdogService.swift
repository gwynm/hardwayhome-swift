import UserNotifications
import os

private let log = Logger(subsystem: "com.gwynmorfey.hardwayhome.native", category: "watchdog")

@MainActor
protocol Watchdog: AnyObject {
    func requestPermission() async
    func arm()
    func disarm()
}

/// Dead man's switch: schedules a local notification that fires if GPS
/// callbacks stop arriving. Each call to `arm()` resets the timer, so the
/// notification only fires if the app is killed and doesn't relaunch.
@MainActor
final class WatchdogService: Watchdog {

    private static let notificationId = "workout-watchdog"
    private static let interval: TimeInterval = 120  // 2 minutes

    func requestPermission() async {
        do {
            try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            log.error("Notification permission request failed: \(error)")
        }
    }

    /// Schedule (or reschedule) the watchdog notification.
    /// Call on every GPS callback to keep pushing the deadline forward.
    func arm() {
        let content = UNMutableNotificationContent()
        content.title = "Workout tracking may have stopped"
        content.body = "Tap to resume tracking."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: Self.interval, repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.notificationId, content: content, trigger: trigger)

        Task {
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                log.error("Failed to schedule watchdog notification: \(error)")
            }
        }
    }

    /// Cancel the watchdog notification. Call on finish/discard.
    func disarm() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.notificationId])
    }
}
