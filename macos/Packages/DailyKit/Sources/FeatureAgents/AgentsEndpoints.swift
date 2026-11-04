import DailyAPI
import DailyModels
import Foundation

/// The calls of the agents screen (`app/api/agents/**`).
///
/// Every task write goes through the server's `local()` receipt, which rejects
/// a request without `Idempotency-Key` and `X-Request-Timestamp`
/// (`lib/agents/operations.ts`, `validateMutation` in `lib/access/receipts.ts:14-17`),
/// so those endpoints are `idempotent` like the web's `mutationHeaders()`.
nonisolated enum AgentsEndpoints {
  /// The board's query (`AgentBoard.tsx:20-26`, workspace mode).
  struct BoardQuery: Equatable, Sendable {
    var tab: AgentsTab = .tasks
    var days: Int = AgentsLogic.defaultActivityWindow
    var sort: AgentsSort = .newest
    var status: AgentTaskStatus?
    var search = ""
    var sessionID: String?
    var cursor: String?

    var items: [URLQueryItem] {
      var items: [URLQueryItem] = []
      // Only "sessions" changes what the server filters (`app/api/agents/route.ts:4`).
      if tab == .sessions { items.append(URLQueryItem(name: "tab", value: "sessions")) }
      if let status { items.append(URLQueryItem(name: "status", value: status.rawValue)) }
      let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
      if !term.isEmpty { items.append(URLQueryItem(name: "q", value: term)) }
      if let sessionID { items.append(URLQueryItem(name: "sessionId", value: sessionID)) }
      if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
      items.append(URLQueryItem(name: "days", value: String(days)))
      items.append(URLQueryItem(name: "scope", value: "roots"))
      items.append(URLQueryItem(name: "sort", value: sort.rawValue))
      items.append(URLQueryItem(name: "limit", value: "100"))
      return items
    }
  }

  /// `POST /api/agents/tasks/{id}/transitions`: `hold` is left out unless the
  /// target is held; an empty note goes as `null`, as `TaskActions.tsx` sends it.
  struct TransitionBody: Encodable, Sendable, Equatable {
    var status: AgentTaskStatus
    var hold: AgentTaskHold?
    var expectedVersion: Int

    private enum Keys: String, CodingKey { case status, hold, expectedVersion }
    private enum HoldKeys: String, CodingKey { case reason, note }

    func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: Keys.self)
      try container.encode(status, forKey: .status)
      try container.encode(expectedVersion, forKey: .expectedVersion)
      guard let hold else { return }
      var nested = container.nestedContainer(keyedBy: HoldKeys.self, forKey: .hold)
      try nested.encode(hold.reason, forKey: .reason)
      try nested.encode(hold.note, forKey: .note)
    }
  }

  /// `PATCH /api/agents/tasks/{id}` from the edit dialog.
  struct EditBody: Encodable, Sendable, Equatable {
    var title: String
    var description: String
    var expectedVersion: Int
  }

  struct MessageBody: Encodable, Sendable, Equatable {
    var text: String
  }

  static func board(_ query: BoardQuery) -> Endpoint<AgentsBoard> {
    Endpoint(.get, "/api/agents", query: query.items)
  }

  /// `cursor` pages the activity and `subtaskCursor` the subtasks (`TaskDetail.tsx:20-24`).
  static func task(id: String, activityCursor: String?, subtaskCursor: String?) -> Endpoint<AgentTaskDetail> {
    var query: [URLQueryItem] = []
    if let activityCursor { query.append(URLQueryItem(name: "cursor", value: activityCursor)) }
    if let subtaskCursor { query.append(URLQueryItem(name: "subtaskCursor", value: subtaskCursor)) }
    return Endpoint(.get, taskPath(id), query: query)
  }

  static func transition(id: String, _ body: TransitionBody) -> Endpoint<AgentTask> {
    Endpoint(.post, taskPath(id) + "/transitions", body: body, idempotent: true)
  }

  static func edit(id: String, _ body: EditBody) -> Endpoint<AgentTask> {
    Endpoint(.patch, taskPath(id), body: body, idempotent: true)
  }

  /// 204 on success.
  static func delete(id: String) -> Endpoint<EmptyResponse> {
    Endpoint(.delete, taskPath(id), idempotent: true)
  }

  static func live(sessionID: String) -> Endpoint<AgentTerminal> {
    Endpoint(.get, sessionPath(sessionID) + "/live")
  }

  static func message(sessionID: String, text: String, key: String) -> Endpoint<AgentMessageReceipt> {
    var endpoint = Endpoint<AgentMessageReceipt>(
      .post, sessionPath(sessionID) + "/messages", body: MessageBody(text: text), idempotent: true)
    endpoint.idempotencyKey = key
    return endpoint
  }

  private static func taskPath(_ id: String) -> String {
    "/api/agents/tasks/\(Endpoint<EmptyResponse>.segment(id))"
  }

  private static func sessionPath(_ id: String) -> String {
    "/api/agents/sessions/\(Endpoint<EmptyResponse>.segment(id))"
  }
}
