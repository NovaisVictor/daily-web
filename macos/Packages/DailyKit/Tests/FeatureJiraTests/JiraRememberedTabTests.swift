import DailyCore
import Foundation
import Testing

@testable import FeatureJira

/// Spec 015 FR-015-01: the tab survives a relaunch, per account.
@MainActor
@Suite struct JiraRememberedTabTests {
  let harness: Harness
  let defaults: UserDefaults

  init() {
    let name = "FeatureJiraTests-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: name) else {
      preconditionFailure("Could not create the defaults suite \(name)")
    }
    self.defaults = defaults
    harness = Harness()
  }

  /// A store as a launch builds it, signed in as `username`.
  func launch(_ username: String = "ana") -> JiraStore {
    let viewState = ViewStateStore(defaults: defaults)
    viewState.activate(server: URL(string: "https://daily.example.com") ?? URL(filePath: "/"), username: username)
    return JiraStore(client: harness.client, dashboard: harness.dashboard, viewState: viewState)
  }

  @Test func tabSurvivesARelaunch() {
    let store = launch()
    store.tab = .problems
    #expect(launch().tab == .problems)
    #expect(launch("bia").tab == JiraStore(client: harness.client, dashboard: harness.dashboard).tab)
  }

  /// Built while the session was still being checked, the store picks up the
  /// account's tab once the sign-in activates it.
  @Test func aStoreBuiltBeforeTheSignInPicksUpTheTab() {
    launch().tab = .problems
    let viewState = ViewStateStore(defaults: defaults)
    viewState.deactivate()
    let store = JiraStore(client: harness.client, dashboard: harness.dashboard, viewState: viewState)
    let fallback = JiraStore(client: harness.client, dashboard: harness.dashboard).tab
    #expect(store.tab == fallback)

    let server = URL(string: "https://daily.example.com") ?? URL(filePath: "/")
    viewState.activate(server: server, username: "ana")
    #expect(store.tab == .problems)
    viewState.activate(server: server, username: "bia")
    #expect(store.tab == fallback)
  }

  @Test func withoutAViewStateNothingIsRemembered() {
    let store = JiraStore(client: harness.client, dashboard: harness.dashboard)
    store.tab = .problems
    #expect(launch().tab != .problems)
  }
}
