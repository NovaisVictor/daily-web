import DailyAPI
import DailyCore
import DailyModels
import UserNotifications
import os

/// The buttons of a system notification about a dashboard notice: "Abrir" and
/// "Marcar como lida".
enum NotificationActions {
  /// The poster must set this as `categoryIdentifier` on alerts that carry a
  /// dashboard notification id in `userInfo[notificationIDKey]`.
  static let dashboardCategory = "dashboard-notification"
  static let notificationIDKey = "notificationID"
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

  /// `markRead` of the bell (`FeatureNotifications/NotificationsStore.swift`): the
  /// badge drops at once and comes back with a toast if the server refuses.
  static func markRead(_ id: String, environment: AppEnvironment) async {
    let failure = await environment.dashboard.mutate { state in
      guard var items = state.notifications.data else { return }
      for index in items.indices where items[index].id == id {
        items[index].read = true
      }
      state.notifications.data = items
    } commit: { () async throws(APIError) in
      _ = try await environment.client.send(markReadEndpoint(id))
    }
    if let failure {
      logger.error("Marking a notification read failed: \(String(describing: failure), privacy: .public)")
    }
  }

  /// `POST /api/notifications/read`; the id goes in the body because it carries
  /// `/`, `#` and `:` (`app/api/notifications/read/route.ts:24-27`).
  private static func markReadEndpoint(_ id: String) -> Endpoint<NotificationsReadResult> {
    Endpoint(.post, "/api/notifications/read", body: ReadBody(id: id))
  }

  private struct ReadBody: Encodable, Sendable {
    let id: String
  }
}
