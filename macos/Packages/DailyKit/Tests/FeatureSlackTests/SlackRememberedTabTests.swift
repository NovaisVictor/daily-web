import DailyAPI
import DailyCore
import Foundation
import Testing

@testable import FeatureSlack

/// Spec 015 FR-015-01: the tab survives a relaunch, per account.
@MainActor
@Suite struct SlackRememberedTabTests {
  let navigator = AppNavigator()
  let dashboard = DashboardStore(client: PreviewAPIClient(responses: [:]), cache: nil, toasts: ToastCenter())
  let defaults: UserDefaults

  init() {
    let name = "FeatureSlackTests-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: name) else {
      preconditionFailure("Could not create the defaults suite \(name)")
    }
    self.defaults = defaults
  }

  func launch(_ username: String = "ana") -> SlackStore {
    let viewState = ViewStateStore(defaults: defaults)
    viewState.activate(server: URL(string: "https://daily.example.com") ?? URL(filePath: "/"), username: username)
    return SlackStore(dashboard: dashboard, navigator: navigator, viewState: viewState)
  }

  @Test func tabSurvivesARelaunch() {
    let store = launch()
    #expect(store.tab == .mentions)
    store.tab = .directs
    #expect(launch().tab == .directs)
    #expect(launch("bia").tab == .mentions)
  }
}
