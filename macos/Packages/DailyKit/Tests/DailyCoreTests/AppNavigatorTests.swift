import SwiftUI
import Testing

@testable import DailyCore

@Suite struct AppNavigatorTests {
  @Test func pendingItemBelongsToItsRoute() {
    let navigator = AppNavigator()
    navigator.open(.module(.email), itemID: "acct:1")
    #expect(navigator.pendingItem(for: .module(.email)) == "acct:1")
    #expect(navigator.pendingItem(for: .agents) == nil)
  }

  @Test func choosingAnotherRouteDropsThePendingItem() {
    let navigator = AppNavigator()
    navigator.open(.module(.email), itemID: "acct:1")
    navigator.route = .agents
    #expect(navigator.pending == nil)
  }

  @Test func finishingClearsOnlyTheSameItem() {
    let navigator = AppNavigator()
    navigator.open(.module(.jira), itemID: "PROJ-1")
    navigator.finishPendingItem("PROJ-2", for: .module(.jira))
    #expect(navigator.pendingItem(for: .module(.jira)) == "PROJ-1")
    navigator.finishPendingItem("PROJ-1", for: .module(.jira))
    #expect(navigator.pending == nil)
  }

  @Test func openingWithoutAnItemClearsTheOldOne() {
    let navigator = AppNavigator()
    navigator.open(.module(.jira), itemID: "PROJ-1")
    navigator.open(.module(.jira))
    #expect(navigator.pending == nil)
  }
}

@Suite struct AppNavigatorRequestTests {
  @Test func settingsTabIsTakenOnce() {
    let navigator = AppNavigator()
    navigator.requestSettings(.profile)
    #expect(navigator.takeRequestedSettingsTab() == .profile)
    #expect(navigator.takeRequestedSettingsTab() == nil)
  }

  @Test func notificationsRequestIsTakenOnce() {
    let navigator = AppNavigator()
    #expect(!navigator.takeNotificationsRequest())
    navigator.requestNotifications()
    #expect(navigator.takeNotificationsRequest())
    #expect(!navigator.isNotificationsRequested)
  }
}

@Suite struct PrimaryWindowTests {
  /// A window that does not say it is the main one never consumes a request.
  @Test func windowsAreNotPrimaryByDefault() {
    #expect(EnvironmentValues().isPrimaryWindow == false)
  }
}
