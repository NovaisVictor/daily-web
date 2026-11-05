import DailyCore
import DailyModels
import Foundation
import Observation

/// The state of the Slack screen (`components/SlackPanel.tsx`). Read-only: the
/// messages come from `state.slack` and open in Slack.
@Observable
final class SlackStore {
  /// Remembered per account across launches (spec 015 FR-015-01).
  var tab: SlackTab {
    get { storedTab }
    set {
      storedTab = newValue
      rememberedTab.save(newValue)
    }
  }
  private var storedTab: SlackTab = .mentions
  var selection: String?

  @ObservationIgnored private let dashboard: DashboardStore
  @ObservationIgnored private let navigator: AppNavigator
  @ObservationIgnored private let rememberedTab: RememberedValue<SlackTab>

  static let viewStateModule = "slack"
  static let tabField = "tab"

  init(dashboard: DashboardStore, navigator: AppNavigator, viewState: ViewStateStore? = nil) {
    self.dashboard = dashboard
    self.navigator = navigator
    rememberedTab = RememberedValue(viewState, module: Self.viewStateModule, field: Self.tabField)
    rememberedTab.bind(self) { [weak self] in self?.storedTab = $0 ?? .mentions }
  }

  static let storeKey = "slack"

  /// The session's one store, shared by the screen and the Início panel so
  /// both show the same tab and selection (spec 011 FR-011-10).
  static func shared(in environment: AppEnvironment) -> SlackStore {
    environment.featureStores.store(storeKey) {
      SlackStore(
        dashboard: environment.dashboard, navigator: environment.navigator, viewState: environment.viewState)
    }
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

  /// The message the list should scroll to once it is on screen.
  var scrollTarget: String?

  private static let route = AppRoute.module(.slack)

  /// The message a clicked notification points at, still waiting to be shown.
  var pendingItemID: String? { navigator.pendingItem(for: Self.route) }

  /// A clicked system notification points at a message: switch to its tab and
  /// select it. The request stays until the digest arrives; with it, the
  /// message is shown or known to be gone.
  func revealPending() {
    guard let id = pendingItemID, let digest = panel?.data else { return }
    navigator.finishPendingItem(id, for: Self.route)
    guard let found = SlackTab.containing(id, in: digest) else { return }
    tab = found
    selection = id
    scrollTarget = id
  }

  /// The address to open; nil when the server sent none (the web renders such a row without a link).
  static func link(_ message: SlackMessage) -> URL? {
    guard !message.url.isEmpty, let url = URL(string: message.url), url.scheme == "https" || url.scheme == "http"
    else { return nil }
    return url
  }
}
