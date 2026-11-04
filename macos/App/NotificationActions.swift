import DailyCore
import FeatureNotifications
import UserNotifications
import os

/// The buttons of a system notification about a dashboard notice: "Abrir" and
/// "Marcar como lida".
enum NotificationActions {
  /// Set by `UserNotificationPoster` on alerts that carry a dashboard notification id.
  static let dashboardCategory = DesktopAlert.dashboardCategory
  static let notificationIDKey = DesktopAlert.notificationIDKey
  static let open = "open"
  static let markRead = "mark-read"

  private static let logger = Logger(subsystem: "io.github.novaisvictor.dailyweb", category: "App")

  static func register(on center: UNUserNotificationCenter) {
    let category = UNNotificationCategory(
      identifier: dashboardCategory,
      actions: [
        UNNotificationAction(identifier: open, title: "Abrir", options: [.foreground]),
        UNNotificationAction(identifier: markRead, title: "Marcar como lida", options: []),
      ],
      intentIdentifiers: []
    )
    center.setNotificationCategories([category])
  }

  /// "Marcar como lida": the bell's own call, so the badge drops at once and
  /// comes back with a toast if the server refuses.
  static func markRead(_ id: String, environment: AppEnvironment) async {
    if let failure = await NotificationsReading.markRead(ids: [id], environment: environment) {
      logger.error("Marking a notification read failed: \(String(describing: failure), privacy: .public)")
    }
  }
}
