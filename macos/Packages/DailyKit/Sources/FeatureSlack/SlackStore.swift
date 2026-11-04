import DailyCore
import DailyModels
import Foundation
import Observation

/// The state of the Slack screen (`components/SlackPanel.tsx`). Read-only: the
/// messages come from `state.slack` and open in Slack.
@Observable
final class SlackStore {
  var tab: SlackTab = .mentions
  var selection: String?

  @ObservationIgnored private let dashboard: DashboardStore
  @ObservationIgnored private let navigator: AppNavigator

  init(dashboard: DashboardStore, navigator: AppNavigator) {
    self.dashboard = dashboard
    self.navigator = navigator
  }

  /// nil until the first state arrives (the web's `loading`).
  var panel: PanelResult<SlackDigest>? { dashboard.state?.slack }

  var isLoading: Bool { panel == nil }
  var team: String { panel?.data?.team ?? "" }
  var error: String? { panel?.error }
  var items: [SlackMessage] { tab.items(in: panel?.data) }

  func count(_ tab: SlackTab) -> Int { tab.items(in: panel?.data).count }

  /// The empty text shows only without an error, as in the web.
  var showsEmpty: Bool { !isLoading && items.isEmpty && error == nil }

  var selectedMessage: SlackMessage? {
    guard let selection else { return nil }
    return items.first { $0.id == selection }
  }

  /// A clicked system notification points at a message: switch to its tab and
  /// select it. Returns the id to scroll to.
  @discardableResult
  func revealPending() -> String? {
    guard let id = navigator.consumePendingItem() else { return nil }
    guard let found = SlackTab.containing(id, in: panel?.data) else { return nil }
    tab = found
    selection = id
    return id
  }

  /// The address to open; nil when the server sent none (the web renders such a row without a link).
  static func link(_ message: SlackMessage) -> URL? {
    guard !message.url.isEmpty, let url = URL(string: message.url), url.scheme == "https" || url.scheme == "http"
    else { return nil }
    return url
  }
}
