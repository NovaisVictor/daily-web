import DailyModels
import Foundation

/// The pure rules of the bell (`components/NotificationsBell.tsx`).
nonisolated enum NotificationsLogic {
  /// The filter entries, in the web's order (`SOURCES`). The web leaves Slack
  /// out although Slack feeds the bell; here it can be filtered too.
  static let filterSources: [NotificationSource] = [.jiraMention, .pullRequest, .email, .slack]

  /// `SOURCE_LABEL`. A source added on the server later shows its raw name.
  static func label(_ source: NotificationSource) -> String {
    switch source {
    case .jiraMention: "JIRA"
    case .pullRequest: "PR"
    case .email: "E-MAIL"
    case .slack: "SLACK"
    default: source.rawValue.uppercased()
    }
  }

  static func unread(_ items: [NotificationItem]) -> [NotificationItem] {
    items.filter { !$0.read }
  }

  /// No source chosen means every source: an empty filter is the whole list.
  static func visible(_ items: [NotificationItem], sources: [NotificationSource]) -> [NotificationItem] {
    sources.isEmpty ? items : items.filter { sources.contains($0.source) }
  }

  /// "notificações (N não lidas)", the bell's `aria-label`.
  static func bellLabel(unread: Int) -> String {
    "notificações (\(unread) não lidas)"
  }

  static func unreadCaption(_ count: Int) -> String {
    count == 1 ? "1 não lida" : "\(count) não lidas"
  }

  // MARK: - Popover size

  /// `w-[min(460px,calc(100vw-2rem))]` (`NotificationsBell.tsx:248-249`).
  static let popoverWidth: CGFloat = 460

  /// `max-h-[70vh]`: 70% of the screen the popover opens on. Without a screen there
  /// is nothing to measure, and the popover takes the height of its content.
  static func popoverMaxHeight(screenHeight: CGFloat?) -> CGFloat? {
    screenHeight.map { ($0 * 0.7).rounded(.down) }
  }

  // MARK: - Jira reply

  /// `COMMENT_MAX`, `lib/jiraLimits.ts:1`.
  static let commentMax = 5000

  private static let mentionPrefix = "jira_mention:"
  /// `JIRA_KEY_PATTERN`, `lib/jiraKey.ts:6`.
  private static var jiraKeyPattern: Regex<Substring> { /^[A-Z][A-Z0-9_]*-\d+$/ }

  /// `isJiraKey`: tested upper-cased, like the web.
  static func isJiraKey(_ value: String) -> Bool {
    value.uppercased().wholeMatch(of: jiraKeyPattern) != nil
  }

  /// `mentionKey`: the issue a Jira mention can be answered on, or nil.
  static func mentionKey(_ item: NotificationItem) -> String? {
    guard item.source == .jiraMention, item.id.hasPrefix(mentionPrefix) else { return nil }
    let key = String(item.id.dropFirst(mentionPrefix.count))
    return isJiraKey(key) ? key : nil
  }

  // MARK: - Marking read

  /// `MAX_IDS` of `app/api/notifications/read/route.ts:9`.
  static let maxIDsPerRequest = 200

  /// The ids in request-sized pieces, in order.
  static func chunks(_ ids: [String], size: Int = maxIDsPerRequest) -> [[String]] {
    stride(from: 0, to: ids.count, by: size).map { Array(ids[$0..<min($0 + size, ids.count)]) }
  }

  /// `markNotificationsRead`, `lib/statePatches.ts:50-59`.
  static func markRead(_ ids: [String], in state: inout DashboardState) {
    guard var items = state.notifications.data, !ids.isEmpty else { return }
    let targets = Set(ids)
    for index in items.indices where targets.contains(items[index].id) {
      items[index].read = true
    }
    state.notifications.data = items
  }

  // MARK: - Opening

  /// The external id of a notification id: everything after the first `:`
  /// (`parseNotificationId`, `lib/notifications.ts:80-89`).
  static func externalID(_ id: String) -> String? {
    guard let cut = id.firstIndex(of: ":"), cut != id.startIndex else { return nil }
    let rest = id[id.index(after: cut)...]
    return rest.isEmpty ? nil : String(rest)
  }

  /// The inbox message an e-mail notification is about, as `account:id`.
  /// The external id is the Message-Id, or `account:id` when the server had
  /// none (`emailNotifications`, `lib/notifications.ts:178-180`).
  static func emailItemID(_ item: NotificationItem, inbox: [EmailEnvelope]) -> String? {
    guard item.source == .email, let external = externalID(item.id) else { return nil }
    let envelope = inbox.first { envelope in
      envelope.messageId.isEmpty ? "\(envelope.account):\(envelope.id)" == external : envelope.messageId == external
    }
    return envelope.map { "\($0.account):\($0.id)" }
  }
}
