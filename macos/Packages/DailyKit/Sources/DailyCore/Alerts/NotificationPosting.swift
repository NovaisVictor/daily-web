import Foundation
import UserNotifications
import os

/// Posts system notifications. The app uses `UserNotificationPoster`; tests use a fake.
public protocol NotificationPosting: AnyObject {
  /// Asks for permission when needed; true when alerts may be shown.
  func requestAuthorization() async -> Bool
  /// True when the user allowed alerts for the app.
  func isAuthorized() async -> Bool
  func post(_ alert: DesktopAlert) async
}

/// `UNUserNotificationCenter`. Build it only inside the app bundle: the center
/// traps when the process has none (`swift test`).
public final class UserNotificationPoster: NotificationPosting {
  private let center: UNUserNotificationCenter

  public init(center: UNUserNotificationCenter = .current()) {
    self.center = center
  }

  public func requestAuthorization() async -> Bool {
    do {
      return try await center.requestAuthorization(options: [.alert, .sound])
    } catch {
      Logger.core.error("Notification permission request failed: \(String(describing: error), privacy: .public)")
      return false
    }
  }

  public func isAuthorized() async -> Bool {
    let status = await center.notificationSettings().authorizationStatus
    return status == .authorized || status == .provisional
  }

  public func post(_ alert: DesktopAlert) async {
    let content = UNMutableNotificationContent()
    content.title = alert.title
    content.body = alert.body
    content.userInfo = alert.target.userInfo
    // Same tag, same notification: a repeat replaces instead of stacking, as
    // the web's `tag` option does.
    let request = UNNotificationRequest(identifier: alert.tag, content: content, trigger: nil)
    do {
      try await center.add(request)
    } catch {
      Logger.core.error("Could not post a notification: \(String(describing: error), privacy: .public)")
    }
  }
}
