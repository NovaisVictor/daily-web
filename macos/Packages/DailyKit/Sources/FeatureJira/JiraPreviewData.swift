import DailyCore
import DailyModels
import Foundation

/// Made-up issues for previews.
enum JiraPreviewData {
  static func issue(
    _ key: String, _ summary: String, kind: String = "História", level: Int? = 0, parent: String? = nil,
    status: String = "Em andamento", category: JiraStatusCategory = .indeterminate, role: JiraRole = .assignee,
    due: String = "", flag: JiraFlag = .none, approval: Bool = false
  ) -> JiraItem {
    JiraItem(
      key: key, summary: summary, status: status, statusCategory: category, project: "TT",
      url: "https://example.atlassian.net/browse/\(key)", parent: parent.map { JiraParent(key: $0, summary: "") },
      role: role, awaitingApproval: approval, kind: kind, subtask: false, hierarchyLevel: level,
      updatedAt: "2026-11-01T10:00:00.000Z", dueDate: due, priority: JiraPriority(name: "Alta", rank: 1), flag: flag)
  }

  static var state: DashboardState {
    var state = PreviewFixtures.dashboard
    state.modules.append(.jira)
    let initiative = issue("TT-10", "Programa de fidelidade", kind: "Iniciativa", level: 2)
    let epic = issue("TT-11", "Pontos por aposta", kind: "Epic", level: 1, parent: "TT-10")
    state.jira = PanelResult(
      data: [
        issue("TT-111", "Tela de saldo", parent: "TT-11", due: "2026-11-06"),
        issue("TT-112", "API de extrato", parent: "TT-11", status: "Backlog", category: .new, flag: .impediment),
        issue("TT-120", "Revisar contrato", role: .reporter, approval: true),
      ],
      error: nil)
    state.jiraAncestors = [initiative, epic]
    state.jiraWatched = PanelResult(data: [issue("XY-5", "Integração do parceiro")], error: nil)
    state.jiraDelivered = PanelResult(
      data: [JiraDatedItem(item: issue("TT-100", "Login social", category: .done), today: true)], error: nil)
    state.jiraApproved = PanelResult(data: [], error: nil)
    state.jiraProblems = PanelResult(
      data: [JiraProblemItem(item: issue("TT-130", "Ajustar extrato"), problems: [.storyWithoutEpic])], error: nil)
    state.jiraFollowedPeople = [JiraPerson(accountId: "acc-1", displayName: "Bruno Teste")]
    return state
  }
}
