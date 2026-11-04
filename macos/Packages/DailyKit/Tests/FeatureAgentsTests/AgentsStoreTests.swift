import DailyAPI
import DailyCore
import DailyModels
import Foundation
import Synchronization
import Testing

@testable import FeatureAgents

/// What the fake server answers per path.
nonisolated final class AgentsServer: Sendable {
  typealias Route = @Sendable (FakeAPIClient.Call) throws(APIError) -> Data?
  private let state: Mutex<(board: AgentsBoard, detail: AgentTaskDetail?, route: Route)>

  init(board: AgentsBoard, detail: AgentTaskDetail? = nil) {
    state = Mutex((board, detail, { _ in nil }))
  }

  func setBoard(_ board: AgentsBoard) { state.withLock { $0.board = board } }
  func setDetail(_ detail: AgentTaskDetail) { state.withLock { $0.detail = detail } }
  func route(_ route: @escaping Route) { state.withLock { $0.route = route } }

  func answer(_ call: FakeAPIClient.Call) throws(APIError) -> Data {
    let (board, detail, route) = state.withLock { ($0.board, $0.detail, $0.route) }
    if let data = try route(call) { return data }
    if call.method == "GET" && call.path == "/api/agents" { return FakeAPIClient.json(board) }
    if call.path.hasPrefix("/api/agents/tasks/"), let detail {
      // Writes answer the task itself (`AgentTask`), reads the whole page.
      if call.method == "GET" { return FakeAPIClient.json(detail) }
      if call.method != "DELETE" { return FakeAPIClient.json(detail.task) }
    }
    return FakeAPIClient.ok
  }
}

/// What the store reported to the alert engine.
@MainActor
final class Reports {
  var items: [[DailyCore.AgentAttention]] = []
}

@MainActor
@Suite struct AgentsStoreTests {
  let client = FakeAPIClient()
  let poller = Poller(sleep: neverWake)
  let server: AgentsServer
  let store: AgentsStore
  let reported = Reports()
  static let now = "2026-10-24T02:00:00.000Z"

  static let waiting = agentTask("w", status: .working, attention: .input, title: "Precisa de mim")
  static let plain = agentTask("p", status: .queued, version: 3, assigned: false)

  init() {
    let server = AgentsServer(board: board([Self.waiting, Self.plain]), detail: detail(Self.plain))
    self.server = server
    client.respond { call throws(APIError) in try server.answer(call) }
    let reported = self.reported
    store = AgentsStore(
      client: client, poller: poller, now: { iso(Self.now) }, sleep: { _ in },
      reportWaiting: { waiting in reported.items.append(waiting) })
  }

  var boardCalls: [FakeAPIClient.Call] { client.calls.filter { $0.path == "/api/agents" } }

  // MARK: - Board

  @Test func loadsTheBoardAndReportsWaitingTasks() async {
    await store.loadBoard()
    #expect(boardCalls.last?.query == "days=3&scope=roots&sort=newest&limit=100")
    #expect(store.tasks.map(\.id) == ["w", "p"])
    #expect(store.waitingOnYou.map(\.id) == ["w"])
    let alerts = reported.items
    #expect(alerts == [[DailyCore.AgentAttention(taskID: "w", title: "Precisa de mim", since: since)]])
  }

  @Test func filteredBoardsDoNotReport() async {
    store.setStatus(.working)
    await settle()
    #expect(boardCalls.last?.query.contains("status=working") == true)
    #expect(reported.items.isEmpty)
  }

  @Test func serverErrorKeepsTheLastBoard() async {
    await store.loadBoard()
    server.route { call throws(APIError) in
      if call.path == "/api/agents" { throw .server(status: 500, message: "boom", code: nil, retry: nil) }
      return nil
    }
    await store.loadBoard()
    #expect(store.board != nil)
    #expect(store.error == "Não foi possível atualizar os dados.")
  }

  @Test func notFoundDropsTheBoard() async {
    await store.loadBoard()
    server.route { _ throws(APIError) in throw .server(status: 404, message: "x", code: "not_found", retry: nil) }
    await store.loadBoard()
    #expect(store.board == nil)
    #expect(store.error == "Este item não está disponível ou expirou.")
  }

  @Test func changingAFilterResetsTheCursorAndReloads() async {
    store.setCursor("next")
    await settle()
    #expect(boardCalls.last?.query.contains("cursor=next") == true)
    store.setDays(7)
    await settle()
    #expect(store.query.cursor == nil)
    #expect(boardCalls.last?.query == "days=7&scope=roots&sort=newest&limit=100")
  }

  @Test func searchFollowsTheFieldAfterThePause() async {
    store.setSearchText("deploy")
    await settle()
    #expect(store.query.search == "deploy")
    #expect(boardCalls.last?.query.contains("q=deploy") == true)
  }

  @Test func showSessionSwitchesToItsTasks() async {
    store.setTab(.sessions)
    store.showSession("s9")
    await settle()
    #expect(store.query.tab == .tasks)
    #expect(store.query.sessionID == "s9")
  }

  // MARK: - Polling

  @Test func pollingScopeFollowsVisibility() async {
    poller.start()
    store.setVisible(true)
    #expect(poller.registeredScopes.contains(Poller.ScopeID.agents))
    await settle()
    // Registering runs at once: reappearing reloads immediately.
    #expect(boardCalls.count == 1)
    store.setVisible(false)
    #expect(!poller.registeredScopes.contains(Poller.ScopeID.agents))
    store.setVisible(true)
    await settle()
    #expect(boardCalls.count == 2)
    poller.stop()
  }

  @Test func liveScopeRunsOnlyWhileATaskWithASessionIsOpenAndVisible() async {
    server.setDetail(detail(Self.waiting))
    store.setVisible(true)
    store.openTask("w")
    await settle()
    #expect(store.detail?.live?.sessionID == "s")
    #expect(poller.registeredScopes.contains(AgentsStore.liveScope))
    store.setVisible(false)
    #expect(!poller.registeredScopes.contains(AgentsStore.liveScope))
    store.setVisible(true)
    #expect(poller.registeredScopes.contains(AgentsStore.liveScope))
    store.closeTask()
    #expect(!poller.registeredScopes.contains(AgentsStore.liveScope))
  }

  @Test func pollReloadsTheOpenDetail() async {
    store.openTask("p")
    await settle()
    await store.poll()
    #expect(client.calls.filter { $0.path == "/api/agents/tasks/p" }.count == 2)
    #expect(store.detail?.live == nil)
  }

  // MARK: - Actions

  func openPlain() async -> AgentTaskDetailStore? {
    store.openTask("p")
    await settle()
    return store.detail
  }

  @Test func transitionSendsTheVersionAndReloads() async throws {
    let detail = try #require(await openPlain())
    #expect(await detail.transition(to: .working))
    let writes = client.calls.filter { $0.method == "POST" }
    #expect(
      writes == [
        FakeAPIClient.Call(
          method: "POST", path: "/api/agents/tasks/p/transitions", query: "",
          body: #"{"expectedVersion":3,"status":"working"}"#, idempotent: true)
      ])
    #expect(client.calls.last?.path == "/api/agents/tasks/p")
  }

  @Test func heldTransitionSendsTheReason() async throws {
    let detail = try #require(await openPlain())
    let hold = try #require(AgentsLogic.hold(status: .blocked, reason: .decision, note: " A ou B "))
    await detail.transition(to: .blocked, hold: hold)
    #expect(
      client.calls.first { $0.method == "POST" }?.body
        == #"{"expectedVersion":3,"hold":{"note":"A ou B","reason":"decision"},"status":"blocked"}"#)
  }

  @Test func versionConflictReloadsAndExplains() async throws {
    let detail = try #require(await openPlain())
    server.route { call throws(APIError) in
      guard call.method == "PATCH" else { return nil }
      throw .server(
        status: 409, message: "Task changed; reload before updating", code: "version_conflict", retry: .reconcile)
    }
    let reads = client.calls.filter { $0.method == "GET" }.count
    // The version the edit started from goes out, even if a poll moved on.
    #expect(!(await detail.edit(title: "Novo", description: "", version: 1)))
    #expect(
      client.calls.first { $0.method == "PATCH" }?.body == #"{"description":"","expectedVersion":1,"title":"Novo"}"#)
    #expect(detail.actionError == "O item mudou. Atualize os dados antes de tentar novamente.")
    #expect(client.calls.filter { $0.method == "GET" }.count == reads + 1)
  }

  @Test func otherFailuresDoNotReload() async throws {
    let detail = try #require(await openPlain())
    server.route { call throws(APIError) in
      guard call.method == "POST" else { return nil }
      throw .server(status: 500, message: "x", code: nil, retry: nil)
    }
    let reads = client.calls.count
    #expect(!(await detail.transition(to: .cancelled)))
    #expect(client.calls.count == reads + 1)
    #expect(detail.actionError == "Não foi possível concluir a operação. Tente novamente.")
  }

  @Test func deleteGoesBackToTheBoard() async throws {
    let detail = try #require(await openPlain())
    #expect(await detail.delete())
    await settle()
    #expect(client.calls.contains { $0.method == "DELETE" && $0.path == "/api/agents/tasks/p" && $0.idempotent })
    #expect(store.detail == nil)
  }

  @Test func deleteWithSubtasksExplains() async throws {
    let detail = try #require(await openPlain())
    server.route { call throws(APIError) in
      guard call.method == "DELETE" else { return nil }
      throw .server(status: 409, message: "x", code: "task_has_subtasks", retry: .reconcile)
    }
    #expect(!(await detail.delete()))
    #expect(detail.actionError == "Exclua as subtarefas antes de excluir a tarefa principal.")
    #expect(store.detail != nil)
  }

  @Test func revealsAPendingTaskByID() async {
    store.openTask("p")
    await settle()
    #expect(store.detail?.taskID == "p")
    #expect(client.calls.contains { $0.path == "/api/agents/tasks/p" })
  }
}

@MainActor
@Suite struct AgentLiveStoreTests {
  let client = FakeAPIClient()
  let poller = Poller(sleep: neverWake)
  let store: AgentLiveStore

  init() {
    store = AgentLiveStore(sessionID: "s1", client: client, poller: poller)
  }

  nonisolated static let terminal = Data(
    #"{"available":true,"live":{"state":"idle","since":null},"pane":"$ ok","response":null,"capturedAt":"2026-10-24T01:00:00.000Z"}"#
      .utf8)

  @Test func loadsTheTerminalOrItsReason() async {
    client.respond { _ in Self.terminal }
    await store.load()
    #expect(store.snapshot?.pane == "$ ok")
    client.respond { _ in Data(#"{"available":false,"reason":"not_local"}"#.utf8) }
    await store.load()
    #expect(store.terminal == .unavailable(.notLocal))
  }

  @Test func sendsTheReplyIdempotentlyAndClearsIt() async {
    client.respond { call in
      call.method == "GET" ? Self.terminal : Data(#"{"ok":true,"id":"m1","state":"queued"}"#.utf8)
    }
    await store.load()
    store.setText("  continue  ")
    await store.send()
    let post = client.calls.last
    #expect(post?.path == "/api/agents/sessions/s1/messages")
    #expect(post?.body == #"{"text":"continue"}"#)
    #expect(post?.idempotent == true)
    #expect(store.text.isEmpty)
    #expect(store.notice?.isError == false)
  }

  @Test func keepsTheDraftWhenDeliveryIsUncertain() async {
    client.respond { _ throws(APIError) in
      throw .server(status: 409, message: "x", code: "uncertain_outcome", retry: .reconcile)
    }
    store.setText("continue")
    await store.send()
    #expect(store.text == "continue")
    #expect(
      store.notice
        == .init(isError: true, text: "Não deu para confirmar a entrega. Confira o terminal antes de reenviar."))
  }

  @Test func retryReusesTheKeyAndAnEditStartsANewOne() async {
    client.respond { _ throws(APIError) in
      throw .server(status: 409, message: "x", code: "uncertain_outcome", retry: .reconcile)
    }
    store.setText("continue")
    await store.send()
    await store.send()
    let keys = client.calls.map(\.idempotencyKey)
    #expect(keys.count == 2)
    #expect(keys[0] != nil && keys[0] == keys[1])
    store.setText("continue já")
    await store.send()
    #expect(client.calls.last?.idempotencyKey != keys[0])
  }

  @Test func capsTheReplyAt4000() {
    store.setText(String(repeating: "a", count: 4100))
    #expect(store.text.count == 4000)
  }

  @Test func startAndStopTheScope() {
    store.start()
    #expect(poller.registeredScopes.contains(AgentsStore.liveScope))
    store.stop()
    #expect(!poller.registeredScopes.contains(AgentsStore.liveScope))
  }
}
