import DailyAPI
import DailyCore
import DailyModels
import Foundation
import Observation
import os

/// The answer being written to a Jira mention (`Reply` and `CommentForm`).
nonisolated struct NotificationReply: Equatable, Sendable {
  enum Stage: Equatable, Sendable {
    case writing
    case published
  }

  var id: String
  var issueKey: String
  var stage: Stage = .writing
  var text = ""
  var sending = false
  var refusal: String?

  var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
  var tooLong: Bool { trimmed.count > NotificationsLogic.commentMax }
  var ready: Bool { !trimmed.isEmpty && !tooLong && !sending }

  /// `problem` in `CommentForm`: the server's refusal, or the length.
  var problem: String? {
    if let refusal { return refusal }
    return tooLong ? "passou de \(NotificationsLogic.commentMax) caracteres (\(trimmed.count))" : nil
  }
}

/// Where a notice leads when opened.
enum NotificationDestination: Equatable {
  /// The item's page (Jira, GitHub, Slack), as the web's link.
  case browser(URL)
  /// A module of the app. The web's e-mail notice has no page; here it opens the message.
  case app(AppRoute, itemID: String?)
}

/// The state and actions of the bell (`components/NotificationsBell.tsx` with
/// `components/shell/HeaderNotifications.tsx`).
@Observable
final class NotificationsStore {
  /// Empty means every source.
  var activeSources: [NotificationSource] = []
  private(set) var markingAll = false
  /// The last failed write, shown inside the popover (`error` in the web).
  var error: String?
  var reply: NotificationReply?
  /// The system refused notifications on the last "Avisar no computador".
  private(set) var alertsDenied = false
  private(set) var changingAlerts = false

  @ObservationIgnored private let client: any APIClient
  @ObservationIgnored private let dashboard: DashboardStore
  @ObservationIgnored private let alerts: AlertEngine
  @ObservationIgnored private let navigator: AppNavigator

  private static let logger = Logger(subsystem: "io.github.novaisvictor.dailyweb", category: "FeatureNotifications")

  init(client: any APIClient, dashboard: DashboardStore, alerts: AlertEngine, navigator: AppNavigator) {
    self.client = client
    self.dashboard = dashboard
    self.alerts = alerts
    self.navigator = navigator
  }

  // MARK: - Derived

  /// `state?.notifications ?? { data: [], error: null }`.
  var panel: PanelResult<[NotificationItem]> {
    dashboard.state?.notifications ?? PanelResult(data: [], error: nil)
  }

  var items: [NotificationItem] { panel.data ?? [] }
  var unread: [NotificationItem] { NotificationsLogic.unread(items) }
  var unreadCount: Int { unread.count }
  var visibleItems: [NotificationItem] { NotificationsLogic.visible(items, sources: activeSources) }
  var alertsEnabled: Bool { alerts.isEnabled }

  func isActive(_ source: NotificationSource) -> Bool { activeSources.contains(source) }

  func toggle(_ source: NotificationSource) {
    if let index = activeSources.firstIndex(of: source) {
      activeSources.remove(at: index)
    } else {
      activeSources.append(source)
    }
  }

  // MARK: - Marking read

  /// The badge drops now; a failure puts the notice back and says why.
  func markRead(_ item: NotificationItem) async {
    error = nil
    let failure = await NotificationsReading.markRead(ids: [item.id], client: client, dashboard: dashboard)
    if let failure { error = failure.userMessage }
  }

  /// "Marcar todas como lidas". The ids are fixed before the call, so a poll
  /// in the middle cannot change what the click meant (`markAllRead`). The
  /// server takes 200 per call, so a longer list goes in pieces.
  func markAllRead() async {
    guard !markingAll, unreadCount > 0 else { return }
    let ids = unread.map(\.id)
    markingAll = true
    defer { markingAll = false }
    error = nil
    let failure = await NotificationsReading.markRead(
      ids: ids, client: client, dashboard: dashboard, alwaysAsList: true)
    if let failure { error = failure.userMessage }
  }

  // MARK: - Replying

  /// "Responder" opens the form; a second click closes it.
  func toggleReply(_ item: NotificationItem) {
    guard let key = NotificationsLogic.mentionKey(item) else { return }
    if reply?.id == item.id, reply?.stage == .writing {
      reply = nil
    } else {
      reply = NotificationReply(id: item.id, issueKey: key)
    }
  }

  func cancelReply() {
    reply = nil
  }

  /// Posts the comment, then marks the mention read (`onPublished`).
  func submitReply() async {
    guard var current = reply, current.stage == .writing, current.ready else { return }
    current.sending = true
    current.refusal = nil
    reply = current
    let body = current.trimmed
    do {
      let response = try await client.send(NotificationsEndpoints.jiraComment(key: current.issueKey, body: body))
      guard reply?.id == current.id else { return }
      guard !response.comment.id.isEmpty else {
        reply?.sending = false
        reply?.refusal = "resposta inesperada do servidor"
        return
      }
      reply = NotificationReply(id: current.id, issueKey: current.issueKey, stage: .published)
      if let item = items.first(where: { $0.id == current.id }), !item.read {
        await markRead(item)
      }
    } catch {
      Self.logger.error("Jira reply failed: \(String(describing: error), privacy: .public)")
      guard reply?.id == current.id else { return }
      reply?.sending = false
      reply?.refusal = error.userMessage
    }
  }

  // MARK: - Desktop alerts

  /// "Avisar no computador": turning on asks the system for permission.
  func toggleAlerts() async {
    if alerts.isEnabled {
      alerts.disable()
      return
    }
    guard !changingAlerts else { return }
    changingAlerts = true
    defer { changingAlerts = false }
    await alerts.enable()
    alertsDenied = !alerts.isEnabled
  }

  // MARK: - Opening

  func destination(_ item: NotificationItem) -> NotificationDestination? {
    if !item.url.isEmpty, let url = URL(string: item.url), url.scheme == "https" || url.scheme == "http" {
      return .browser(url)
    }
    guard item.source == .email, dashboard.state?.modules.contains(.email) == true else { return nil }
    let inbox = dashboard.state?.email.data ?? []
    return .app(.module(.email), itemID: NotificationsLogic.emailItemID(item, inbox: inbox))
  }

  func navigate(_ route: AppRoute, itemID: String?) {
    navigator.open(route, itemID: itemID)
  }
}
