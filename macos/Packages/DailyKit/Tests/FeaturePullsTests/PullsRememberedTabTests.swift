import DailyCore
import Foundation
import Testing

@testable import FeaturePulls

/// Spec 015 FR-015-01: the tab survives a relaunch, per account.
@MainActor
@Suite struct PullsRememberedTabTests {
  let harness: Harness
  let defaults: UserDefaults

  init() {
    let name = "FeaturePullsTests-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: name) else {
      preconditionFailure("Could not create the defaults suite \(name)")
    }
    self.defaults = defaults
    harness = Harness()
  }

  /// A store as a launch builds it, signed in as `username`.
  func launch(_ username: String = "ana") -> PullsStore {
    let viewState = ViewStateStore(defaults: defaults)
    viewState.activate(server: URL(string: "https://daily.example.com") ?? URL(filePath: "/"), username: username)
    return PullsStore(client: harness.client, dashboard: harness.dashboard, viewState: viewState)
  }

  @Test func tabSurvivesARelaunch() {
    let store = launch()
    store.tab = .mine
    #expect(launch().tab == .mine)
    #expect(launch("bia").tab == PullsStore(client: harness.client, dashboard: harness.dashboard).tab)
  }

  @Test func withoutAViewStateNothingIsRemembered() {
    let store = PullsStore(client: harness.client, dashboard: harness.dashboard)
    store.tab = .mine
    #expect(launch().tab != .mine)
  }
}
