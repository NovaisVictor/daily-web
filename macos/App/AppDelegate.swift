import AppKit
import DailyCore
import DailyStorage
import UserNotifications

/// Owns the object graph so notification clicks, which arrive here, can reach
/// the same navigator the window uses.
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
  let environment = AppEnvironment(
    settings: UserDefaultsServerSettings(),
    tokenStore: KeychainSessionTokenStore()
  )

  func applicationDidFinishLaunching(_ notification: Notification) {
    UNUserNotificationCenter.current().delegate = self
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
    // Screens register pending writes (a note's autosave); quit once they land.
    Task {
      await environment.shutdown.flushAll()
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // The menu bar item (T501) keeps polling for alerts with no window open.
    false
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
    await MainActor.run {
      guard let target = AlertTarget(userInfo: captured) else { return }
      environment.navigator.open(target)
      NSApp.activate()
    }
  }
}
