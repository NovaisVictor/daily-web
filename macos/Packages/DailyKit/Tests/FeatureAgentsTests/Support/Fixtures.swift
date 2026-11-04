import DailyModels
import Foundation

@testable import FeatureAgents

nonisolated let since = "2026-10-24T01:00:00.000Z"

/// `task()` of `tests/components/agents/NeedsYou.test.ts`.
nonisolated func agentTask(
  _ id: String = "t",
  status: AgentTaskStatus,
  attention: AgentAttentionKind? = nil,
  live: AgentLiveState? = nil,
  hold: AgentTaskHold? = nil,
  version: Int = 1,
  parent: String? = nil,
  lastActivityAt: String = since,
  assigned: Bool = true,
  title: String = "Ship"
) -> AgentTask {
  AgentTask(
    id: id, parentTaskId: parent, externalId: id, title: title, description: "", status: status, hold: hold,
    assignment: assigned
      ? AgentAssignment(
        sessionId: "s", agentId: "a", provider: .claude, displayName: "Claude", freshness: .fresh,
        attention: attention.map { DailyModels.AgentAttention(kind: $0, since: since) },
        live: live.map { AgentLive(state: $0, since: since) })
      : nil,
    source: nil, version: version, createdAt: since, lastActivityAt: lastActivityAt)
}

nonisolated func board(_ tasks: [AgentTask], counts: [String: Int] = [:], next: String? = nil) -> AgentsBoard {
  AgentsBoard(
    tasks: AgentPage(items: tasks, nextCursor: next, complete: true),
    sessions: AgentPage(items: [], nextCursor: nil, complete: true),
    subtaskProgress: [:], statusCounts: counts)
}

nonisolated func detail(_ task: AgentTask) -> AgentTaskDetail {
  AgentTaskDetail(
    task: task, activity: AgentPage(items: [], nextCursor: nil, complete: true),
    subtasks: AgentPage(items: [], nextCursor: nil, complete: true))
}

nonisolated func iso(_ text: String) -> Date {
  guard let date = AgentsLogic.date(text) else { preconditionFailure("Bad test date \(text)") }
  return date
}
