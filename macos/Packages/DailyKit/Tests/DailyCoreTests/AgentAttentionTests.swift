import DailyAPI
import DailyModels
import Foundation
import Testing

@testable import DailyCore

nonisolated private let since = "2026-11-04T11:00:00.000Z"
nonisolated private let now = AgentAttentionRules.date("2026-11-04T12:00:00.000Z") ?? .distantPast

nonisolated private func agentTask(
  _ id: String,
  status: AgentTaskStatus,
  attention: AgentAttentionKind? = nil,
  live: AgentLiveState? = nil,
  parent: String? = nil,
  lastActivityAt: String = since
) -> AgentTask {
  AgentTask(
    id: id, parentTaskId: parent, externalId: id, title: "Tarefa \(id)", description: "", status: status,
    hold: nil,
    assignment: AgentAssignment(
      sessionId: "s", agentId: "a", provider: .claude, displayName: "Claude", freshness: .fresh,
      attention: attention.map { DailyModels.AgentAttention(kind: $0, since: since) },
      live: live.map { AgentLive(state: $0, since: since) }),
    source: nil, version: 1, createdAt: since, lastActivityAt: lastActivityAt)
}

nonisolated private func board(_ tasks: [AgentTask]) -> AgentsBoard {
  AgentsBoard(
    tasks: AgentPage(items: tasks, nextCursor: nil, complete: true),
    sessions: AgentPage(items: [], nextCursor: nil, complete: true),
    subtaskProgress: [:], statusCounts: [:])
}

@Suite struct AgentAttentionRulesTests {
  @Test func waitingKeepsRootTasksOfTheDefaultWindowThatNeedTheUser() {
    let tasks = [
      agentTask("ask", status: .working, attention: .permission),
      agentTask("busy", status: .working, attention: .input, live: .working),
      agentTask("child", status: .working, attention: .input, parent: "ask"),
      agentTask("old", status: .working, attention: .input, lastActivityAt: "2026-10-01T00:00:00.000Z"),
      agentTask("done", status: .completed, attention: .input),
    ]
    let waiting = AgentAttentionRules.waiting(board(tasks), now: now)
    #expect(
      waiting == [AgentAttention(taskID: "ask", title: "Tarefa ask", since: since, kind: "permission", agent: "Claude")]
    )
  }

  @Test func defaultBoardIsTheScreensFirstQuery() {
    let endpoint = AgentAttentionRules.defaultBoard
    #expect(endpoint.path == "/api/agents")
    #expect(
      endpoint.query.map { "\($0.name)=\($0.value ?? "")" } == ["days=3", "scope=roots", "sort=newest", "limit=100"])
  }
}

@MainActor
@Suite struct AgentAttentionCheckTests {
  let client = FakeAPIClient()
  let poster = FakeNotificationPoster()
  let alerts: AlertEngine
  let clock = Clock(now)

  /// A settable time the engine and the check share.
  final class Clock {
    var date: Date
    init(_ date: Date) { self.date = date }
  }

  init() {
    let defaults = Fixtures.defaults()
    defaults.set("1", forKey: AlertEngine.enabledKey)
    let clock = clock
    alerts = AlertEngine(poster: poster, cache: nil, defaults: defaults, now: { clock.date })
  }

  func makeCheck() -> AgentAttentionCheck {
    let clock = clock
    return AgentAttentionCheck(client: client, alerts: alerts, now: { clock.date })
  }

  @Test func alertsANewWaitWithoutTheScreen() async {
    let check = makeCheck()
    client.respond { _ in FakeAPIClient.json(board([agentTask("a", status: .working)])) }
    await check.run()
    client.respond { _ in FakeAPIClient.json(board([agentTask("a", status: .working, attention: .input)])) }
    await check.run()
    #expect(client.calls.map(\.path) == ["/api/agents", "/api/agents"])
    #expect(poster.posted.map(\.title) == ["Aguardando sua resposta: Tarefa a"])
  }

  @Test func staysQuietWhileTheScreenReportsTheUnfilteredBoard() async {
    await alerts.updateAgentsFromScreen([])
    clock.date = now.addingTimeInterval(30)
    await makeCheck().run()
    #expect(client.calls.isEmpty)
  }

  /// Hidden (the screen's scope is paused in the background), filtered or on
  /// "Sessões", the screen stops reporting; the check must read the board again.
  @Test func readsAgainOnceTheScreenStopsReporting() async {
    await alerts.updateAgentsFromScreen([])
    clock.date = now.addingTimeInterval(61)
    client.respond { _ in FakeAPIClient.json(board([agentTask("a", status: .working, attention: .input)])) }
    await makeCheck().run()
    #expect(client.calls.map(\.path) == ["/api/agents"])
  }

  @Test func readsWhenTheScreenNeverReported() async {
    let poller = Poller(sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
    // A registered but paused or filtered screen used to silence the check.
    poller.register(Poller.ScopeID.agents, foreground: .seconds(2), background: nil) {}
    client.respond { _ in FakeAPIClient.json(board([])) }
    await makeCheck().run()
    #expect(client.calls.map(\.path) == ["/api/agents"])
  }

  @Test func dropsItsAnswerWhenTheScreenReportedMeanwhile() async {
    let check = makeCheck()
    let alerts = alerts
    client.respond { _ in FakeAPIClient.json(board([agentTask("a", status: .working, attention: .input)])) }
    await check.run()
    client.respond { _ in
      await alerts.updateAgentsFromScreen([])
      return FakeAPIClient.json(board([agentTask("b", status: .working, attention: .input)]))
    }
    await check.run()
    #expect(poster.posted.isEmpty)
  }

  @Test func aFailedReadKeepsWhatWasSeen() async {
    let check = makeCheck()
    client.respond { _ in FakeAPIClient.json(board([agentTask("a", status: .working, attention: .input)])) }
    await check.run()
    client.respond { _ throws(APIError) in throw APIError.server(status: 500, message: "falhou", code: nil, retry: nil)
    }
    await check.run()
    client.respond { _ in FakeAPIClient.json(board([agentTask("a", status: .working, attention: .input)])) }
    await check.run()
    #expect(poster.posted.isEmpty)
  }

  @Test func appEnvironmentRegistersTheMinuteCheck() {
    let environment = AppEnvironment(
      rawClient: client, tokenStore: InMemorySessionStorage(server: nil, token: nil),
      settings: InMemorySessionStorage(server: nil, token: nil), cacheDirectory: nil, defaults: Fixtures.defaults(),
      poster: poster)
    #expect(environment.poller.registeredScopes.contains(Poller.ScopeID.agentAttention))
  }
}
