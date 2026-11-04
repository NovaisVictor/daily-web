import DailyAPI
import DailyModels
import Foundation
import Testing

@testable import FeatureAgents

@Suite struct AgentsEndpointsTests {
  func query(_ items: [URLQueryItem]) -> String {
    items.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
  }

  @Test func boardQueryDefaults() {
    let endpoint = AgentsEndpoints.board(AgentsEndpoints.BoardQuery())
    #expect(endpoint.method == .get)
    #expect(endpoint.path == "/api/agents")
    #expect(query(endpoint.query) == "days=3&scope=roots&sort=newest&limit=100")
  }

  @Test func boardQueryWithFilters() {
    var board = AgentsEndpoints.BoardQuery()
    board.tab = .sessions
    board.status = .blocked
    board.search = "  deploy "
    board.sessionID = "s1"
    board.cursor = "abc"
    board.days = 7
    board.sort = .oldest
    #expect(
      query(board.items)
        == "tab=sessions&status=blocked&q=deploy&sessionId=s1&cursor=abc&days=7&scope=roots&sort=oldest&limit=100")
  }

  @Test func detailPagesBothCursors() {
    let endpoint = AgentsEndpoints.task(id: "a/b", activityCursor: "c1", subtaskCursor: "c2")
    #expect(endpoint.path == "/api/agents/tasks/a%2Fb")
    #expect(query(endpoint.query) == "cursor=c1&subtaskCursor=c2")
    #expect(AgentsEndpoints.task(id: "t", activityCursor: nil, subtaskCursor: nil).query.isEmpty)
  }

  @Test func writesCarryVersionAndIdempotency() {
    let plain = AgentsEndpoints.transition(
      id: "t", AgentsEndpoints.TransitionBody(status: .completed, hold: nil, expectedVersion: 4))
    #expect(plain.method == .post)
    #expect(plain.path == "/api/agents/tasks/t/transitions")
    #expect(plain.idempotent)
    #expect(FakeAPIClient.encode(plain.body) == #"{"expectedVersion":4,"status":"completed"}"#)

    let held = AgentsEndpoints.TransitionBody(
      status: .blocked, hold: AgentTaskHold(reason: .access, note: nil), expectedVersion: 2)
    #expect(
      FakeAPIClient.encode(held) == #"{"expectedVersion":2,"hold":{"note":null,"reason":"access"},"status":"blocked"}"#)

    let edit = AgentsEndpoints.edit(
      id: "t", AgentsEndpoints.EditBody(title: "T", description: "D", expectedVersion: 1))
    #expect(edit.method == .patch)
    #expect(edit.path == "/api/agents/tasks/t")
    #expect(edit.idempotent)
    #expect(FakeAPIClient.encode(edit.body) == #"{"description":"D","expectedVersion":1,"title":"T"}"#)

    let delete = AgentsEndpoints.delete(id: "t")
    #expect(delete.method == .delete)
    #expect(delete.idempotent)
  }

  @Test func liveAndMessages() {
    #expect(AgentsEndpoints.live(sessionID: "s 1").path == "/api/agents/sessions/s%201/live")
    let message = AgentsEndpoints.message(sessionID: "s", text: "oi", key: "k1")
    #expect(message.idempotencyKey == "k1")
    #expect(message.method == .post)
    #expect(message.path == "/api/agents/sessions/s/messages")
    #expect(message.idempotent)
    #expect(FakeAPIClient.encode(message.body) == #"{"text":"oi"}"#)
  }
}
