import DailyModels
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

@Suite struct AppRouteTests {
  /// Every route a notification can carry survives the trip through `userInfo`.
  @Test(arguments: [
    AppRoute.today, .agents, .access, .kanban, .ferramentas, .configuracao, .perfil, .module(.jira),
    .module(ModuleID(rawValue: "future")),
  ])
  func routeRoundTripsThroughUserInfo(route: AppRoute) {
    let target = AlertTarget(route: route, itemID: "x")
    let info: [AnyHashable: Any] = target.userInfo.reduce(into: [:]) { $0[$1.key] = $1.value }
    #expect(AlertTarget(userInfo: info) == target)
  }

  @Test func newRoutesHaveStableNames() {
    #expect(AlertTarget.encode(.kanban) == "kanban")
    #expect(AlertTarget.encode(.ferramentas) == "ferramentas")
    #expect(AlertTarget.encode(.configuracao) == "configuracao")
    #expect(AlertTarget.encode(.perfil) == "perfil")
    #expect(AlertTarget.decode("nope") == nil)
  }

  @Test func openingANewRouteMovesTheWindow() {
    let navigator = AppNavigator()
    navigator.open(.configuracao)
    #expect(navigator.route == .configuracao)
  }
}
