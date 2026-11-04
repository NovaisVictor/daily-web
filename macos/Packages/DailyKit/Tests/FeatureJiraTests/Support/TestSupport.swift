import DailyAPI
import DailyCore
import DailyModels
import Foundation

@testable import FeatureJira

/// An issue with the web tests' defaults (`tests/lib/jiraOrder.test.ts:6-24`).
func makeIssue(
  _ key: String,
  summary: String? = nil,
  status: String = "Em andamento",
  category: JiraStatusCategory = .indeterminate,
  parent: String? = nil,
  role: JiraRole = .assignee,
  approval: Bool = false,
  kind: String = "História",
  subtask: Bool = false,
  level: Int? = 0,
  updatedAt: String = "2026-10-10T10:00:00Z",
  due: String = "",
  priority: JiraPriority? = nil,
  flag: JiraFlag = .none
) -> JiraItem {
  JiraItem(
    key: key, summary: summary ?? key, status: status, statusCategory: category,
    project: String(key.split(separator: "-")[0]), url: "https://acme.atlassian.net/browse/\(key)",
    parent: parent.map { JiraParent(key: $0, summary: "Resumo \($0)") }, role: role, awaitingApproval: approval,
    kind: kind, subtask: subtask, hierarchyLevel: level, updatedAt: updatedAt, dueDate: due, priority: priority,
    flag: flag)
}

/// `raw` in `tests/lib/jiraFilters.test.ts:18-33`: what `toJiraItem` makes of
/// a Jira answer with this instance's levels.
func raw(
  _ key: String, _ type: String, _ level: Int, _ parent: String? = nil, summary: String? = nil,
  status: String = "Em Andamento", category: JiraStatusCategory = .indeterminate
) -> JiraItem {
  makeIssue(
    key, summary: summary ?? "Resumo \(key)", status: status, category: category, parent: parent, kind: type,
    subtask: level < 0, level: level)
}

func makeState(
  jira: [JiraItem] = [],
  watched: [JiraItem] = [],
  people: [JiraPerson] = [],
  problems: [JiraProblemItem] = []
) -> DashboardState {
  var state = PreviewFixtures.dashboard
  state.modules.append(.jira)
  state.jira = PanelResult(data: jira, error: nil)
  state.jiraWatched = PanelResult(data: watched, error: nil)
  state.jiraFollowedPeople = people
  state.jiraDelivered = PanelResult(data: [], error: nil)
  state.jiraApproved = PanelResult(data: [], error: nil)
  state.jiraProblems = PanelResult(data: problems, error: nil)
  return state
}

/// Lets every ready main-actor task run.
@MainActor
func settle() async {
  for _ in 0..<200 { await Task.yield() }
}

/// A store over a fake client whose `GET /api/state` answers `server`.
@MainActor
final class Harness {
  let client: FakeAPIClient
  let dashboard: DashboardStore
  let toasts: ToastCenter
  let store: JiraStore

  /// `loaded: false` leaves the dashboard without a server state, as at launch.
  init(
    _ state: DashboardState = makeState(), loaded: Bool = true, now: Date = Date(timeIntervalSince1970: 1_790_000_000)
  ) {
    let client = FakeAPIClient()
    self.client = client
    let toasts = ToastCenter(sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
    self.toasts = toasts
    dashboard = DashboardStore(client: client, cache: nil, toasts: toasts)
    store = JiraStore(client: client, dashboard: dashboard, now: { now })
    if loaded { dashboard.apply(state) }
    serve(state: state)
  }

  /// Answers writes with `write` and the dashboard read with `state`.
  func serve(
    state: DashboardState,
    write: @escaping @Sendable (FakeAPIClient.Call) async throws(APIError) -> Data = { _ in FakeAPIClient.ok }
  ) {
    let stateData = FakeAPIClient.json(state)
    client.respond { call throws(APIError) in
      if call.path == "/api/state" { return stateData }
      return try await write(call)
    }
  }

  /// Writes fail with the server's message; the read fails too, so the state
  /// on screen is exactly what the rollback left.
  func failWrites(_ message: String = "falhou", status: Int = 400) {
    client.respond { call throws(APIError) in
      if call.path == "/api/state" { throw .offline }
      throw .server(status: status, message: message, code: nil, retry: nil)
    }
  }
}
