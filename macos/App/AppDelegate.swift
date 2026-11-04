import AppKit
import DailyCore
import DailyStorage
import FeatureShell
import UserNotifications
import os

/// Owns the object graph so notification clicks, which arrive here, can reach
/// the same navigator the window uses.
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
  let environment = AppEnvironment(
    settings: UserDefaultsServerSettings(),
    tokenStore: KeychainSessionTokenStore()
  )
  let opener = WindowOpener()

  private static let logger = Logger(subsystem: "io.github.novaisvictor.dailyweb", category: "App")

  func applicationDidFinishLaunching(_ notification: Notification) {
    UNUserNotificationCenter.current().delegate = self
    NotificationActions.register(on: .current())
    GlobalShortcut.install { [opener] in opener.showMain() }
    // Once per process: a second window must not restore an already live session.
    Task { await environment.launch() }
    updateForeground()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(occlusionChanged),
      name: NSApplication.didChangeOcclusionStateNotification,
      object: nil
    )
  }

  /// FR-003 counts "some window visible" as foreground, not "app focused": a
  /// dashboard left on a second monitor keeps the 20 s cadence.
  @objc private func occlusionChanged(_ notification: Notification) {
    updateForeground()
  }

  private func updateForeground() {
    environment.setForeground(NSApp.occlusionState.contains(.visible))
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    // Screens register pending writes (a note's autosave); quit once they land,
    // but never hold the quit longer than a few seconds on a hung server: the
    // unsaved text is the price of not blocking logout or shutdown.
    Task {
      await withTaskGroup(of: Void.self) { group in
        group.addTask { await self.environment.shutdown.flushAll() }
        group.addTask { try? await Task.sleep(for: .seconds(5)) }
        await group.next()
        group.cancelAll()
      }
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // The menu bar item (T501) keeps polling for alerts with no window open.
    false
  }

  /// A Dock click with every window closed brings the main window back; the menu
  /// bar item keeps the app running meanwhile.
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    guard !flag else { return true }
    opener.showMain()
    return false
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    // The web shows its alerts even when the tab is focused; do the same.
    [.banner, .sound, .list]
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    // userInfo is not Sendable; copy the string pairs before hopping actors.
    var info: [String: String] = [:]
    for (key, value) in response.notification.request.content.userInfo {
      if let key = key as? String, let value = value as? String { info[key] = value }
    }
    let captured = info
    let action = response.actionIdentifier
    await MainActor.run {
      handle(action: action, userInfo: captured)
    }
  }

  private func handle(action: String, userInfo: [String: String]) {
    switch action {
    case NotificationActions.markRead:
      guard let id = userInfo[NotificationActions.notificationIDKey] else {
        Self.logger.error("A \"Marcar como lida\" action came without a notification id")
        return
      }
      Task { await NotificationActions.markRead(id, environment: environment) }
    case NotificationActions.open, UNNotificationDefaultActionIdentifier:
      guard let target = AlertTarget(userInfo: userInfo) else {
        Self.logger.error("A clicked notification had no target")
        opener.showMain()
        return
      }
      environment.navigator.open(target)
      opener.showMain()
    case UNNotificationDismissActionIdentifier:
      return
    default:
      Self.logger.error("Unknown notification action \(action, privacy: .public)")
    }
  }
}
