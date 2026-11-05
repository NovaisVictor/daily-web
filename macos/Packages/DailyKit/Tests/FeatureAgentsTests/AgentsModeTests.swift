import DailyAPI
import DailyCore
import DailyModels
import Foundation
import Testing

@testable import FeatureAgents

/// `AgentBoard({ mode })`: the Kanban page and the agents workspace.
@Suite struct AgentsModeTests {
  @Test func kanbanHasItsTitleAndNoTabs() {
    #expect(AgentsMode.kanban.title == "Kanban de tarefas")
    #expect(!AgentsMode.kanban.showsTabs)
  }

  @Test func workspaceKeepsTheSessionsTab() {
    #expect(AgentsMode.workspace.title == "Agentes e atividades")
    #expect(AgentsMode.workspace.showsTabs)
  }

  /// `grid-cols-1 sm:grid-cols-2 lg:grid-cols-4` (`BoardViews.tsx:42`).
  @Test func activeColumnsFollowTheWidth() {
    #expect(AgentsLogic.columnCount(width: 320, columns: 4) == 1)
    #expect(AgentsLogic.columnCount(width: 639, columns: 4) == 1)
    #expect(AgentsLogic.columnCount(width: 640, columns: 4) == 2)
    #expect(AgentsLogic.columnCount(width: 1023, columns: 4) == 2)
    #expect(AgentsLogic.columnCount(width: 1024, columns: 4) == 4)
    #expect(AgentsLogic.columnCount(width: 1600, columns: 4) == 4)
  }

  /// `lg:grid-cols-3` for the finished ones (`BoardViews.tsx:50`).
  @Test func finishedColumnsStopAtThree() {
    #expect(AgentsLogic.columnCount(width: 500, columns: 3) == 1)
    #expect(AgentsLogic.columnCount(width: 800, columns: 3) == 2)
    #expect(AgentsLogic.columnCount(width: 1200, columns: 3) == 3)
  }

  @Test func neverFewerThanOneColumn() {
    #expect(AgentsLogic.columnCount(width: 0, columns: 1) == 1)
    #expect(AgentsLogic.columnCount(width: 2000, columns: 1) == 1)
  }
}

/// A system notification center that answers as told.
@MainActor
final class FakeNotificationPoster: NotificationPosting {
  var grants: Bool
  private(set) var requests = 0
  private(set) var posted: [DesktopAlert] = []

  init(grants: Bool) {
    self.grants = grants
  }

  func requestAuthorization() async -> Bool {
    requests += 1
    return grants
  }

  func isAuthorized() async -> Bool { grants }
  func post(_ alert: DesktopAlert) async { posted.append(alert) }
}

@MainActor
@Suite struct AgentsBoardModeStoreTests {
  let client = FakeAPIClient()

  init() {
    client.respond { _ throws(APIError) in FakeAPIClient.json(board([])) }
  }

  func makeStore(mode: AgentsMode, alerts: AlertEngine? = nil) -> AgentsStore {
    AgentsStore(
      client: client, poller: Poller(sleep: neverWake), mode: mode, alerts: alerts,
      now: { iso("2026-10-24T02:00:00.000Z") }, sleep: { _ in })
  }

  func makeAlerts(_ poster: FakeNotificationPoster) throws -> AlertEngine {
    let defaults = try #require(UserDefaults(suiteName: "agents-alerts-\(UUID().uuidString)"))
    return AlertEngine(poster: poster, cache: nil, defaults: defaults)
  }

  @Test func kanbanIgnoresTheSessionsTab() async {
    let store = makeStore(mode: .kanban)
    store.setTab(.sessions)
    await settle()
    #expect(store.query.tab == .tasks)
    #expect(client.calls.isEmpty)
  }

  @Test func workspaceSwitchesToSessions() async {
    let store = makeStore(mode: .workspace)
    store.setTab(.sessions)
    await settle()
    #expect(store.query.tab == .sessions)
    #expect(client.calls.last?.query.contains("tab=sessions") == true)
  }

  @Test func withoutAnAlertEngineTheToggleIsHidden() {
    #expect(makeStore(mode: .kanban).alertsState == .unavailable)
  }

  @Test func enablingAsksPermissionAndTurnsTheAlertsOn() async throws {
    let poster = FakeNotificationPoster(grants: true)
    let alerts = try makeAlerts(poster)
    let store = makeStore(mode: .kanban, alerts: alerts)
    #expect(store.alertsState == .off)

    await store.enableAlerts()

    #expect(poster.requests == 1)
    #expect(alerts.isEnabled)
    #expect(store.alertsState == .on)
    #expect(store.alertsNotice == "Avisos ativados neste dispositivo.")
  }

  @Test func refusedPermissionShowsBlocked() async throws {
    let poster = FakeNotificationPoster(grants: false)
    let alerts = try makeAlerts(poster)
    let store = makeStore(mode: .kanban, alerts: alerts)

    await store.enableAlerts()

    #expect(!alerts.isEnabled)
    #expect(store.alertsState == .denied)
    #expect(store.alertsNotice == nil)
  }

  @Test func testingPostsALocalNoticeWhileOn() async throws {
    let poster = FakeNotificationPoster(grants: true)
    let alerts = try makeAlerts(poster)
    await alerts.enable()
    let store = makeStore(mode: .kanban, alerts: alerts)

    await store.testAlert()

    #expect(poster.posted.map(\.tag) == ["agents-test"])
    #expect(store.alertsNotice == "Aviso de teste enviado.")
  }

  @Test func disablingTurnsTheSharedSwitchOff() async throws {
    let poster = FakeNotificationPoster(grants: true)
    let alerts = try makeAlerts(poster)
    await alerts.enable()
    let store = makeStore(mode: .kanban, alerts: alerts)
    #expect(store.alertsState == .on)

    store.disableAlerts()

    #expect(!alerts.isEnabled)
    #expect(store.alertsState == .off)
    #expect(store.alertsNotice == "Avisos desativados neste dispositivo.")
  }
}
