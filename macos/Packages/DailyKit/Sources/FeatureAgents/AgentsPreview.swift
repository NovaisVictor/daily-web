import DailyAPI
import DailyCore
import DailyModels
import Foundation
import os

/// Sample board for previews; names and texts are made up.
enum AgentsPreview {
  static let now = "2026-11-04T12:40:00.000Z"

  static func task(
    _ id: String,
    _ title: String,
    status: AgentTaskStatus,
    hold: AgentTaskHold? = nil,
    attention: DailyModels.AgentAttention? = nil
  ) -> AgentTask {
    AgentTask(
      id: id, parentTaskId: nil, externalId: "ext-\(id)", title: title, description: "", status: status, hold: hold,
      assignment: AgentAssignment(
        sessionId: "session-1", agentId: "agent-1", provider: .claude, displayName: "Claude no notebook",
        freshness: .fresh, attention: attention),
      source: nil, version: 1, createdAt: now, lastActivityAt: now)
  }

  static var board: AgentsBoard {
    AgentsBoard(
      tasks: AgentPage(
        items: [
          task("1", "Revisar migração do relatório", status: .working),
          task(
            "2", "Escolher a biblioteca de gráficos", status: .blocked,
            hold: AgentTaskHold(reason: .decision, note: "A ou B")),
          task("3", "Aguardar CI do PR #81", status: .waiting, hold: AgentTaskHold(reason: .build, note: nil)),
          task("4", "Atualizar dependências", status: .completed),
        ],
        nextCursor: nil, complete: true),
      sessions: AgentPage(items: [], nextCursor: nil, complete: true),
      subtaskProgress: [:],
      statusCounts: ["completed": 1])
  }

  /// A store whose client answers the sample board and nothing touches the network.
  static func store(mode: AgentsMode = .workspace) -> AgentsStore {
    var responses: [String: Data] = [:]
    do {
      responses["GET /api/agents"] = try JSONEncoder().encode(board)
    } catch {
      Logger.agents.fault("Preview board failed to encode: \(String(describing: error), privacy: .public)")
    }
    let store = AgentsStore(
      client: PreviewAPIClient(responses: responses), poller: Poller(), mode: mode,
      now: { AgentsLogic.date(now) ?? Date() })
    Task { await store.loadBoard() }
    return store
  }
}
