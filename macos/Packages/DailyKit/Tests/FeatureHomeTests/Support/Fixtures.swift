import DailyModels
import Foundation

/// Builders for dashboard states; names and addresses are made up.
enum Fixtures {
  /// 2026-11-04 (a Wednesday) at 13:15:07 in São Paulo.
  static let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo") ?? .gmt
    return calendar
  }()

  static let now: Date = {
    let parts = DateComponents(year: 2026, month: 11, day: 4, hour: 13, minute: 15, second: 7)
    guard let date = calendar.date(from: parts) else { preconditionFailure("Invalid fixture date") }
    return date
  }()

  static func task(_ id: String, due: String, completed: Bool = false, priority: TaskPriority = .normal) -> TodoTask {
    TodoTask(
      id: id, title: "Tarefa \(id)", completed: completed, due: due, priority: priority, time: "", recur: "",
      notes: "", subtasks: [], doing: false, paper: nil, pin: nil, pinShape: nil)
  }

  static func email(_ id: String, unread: Bool) -> EmailEnvelope {
    EmailEnvelope(
      id: id, account: "conn-1", accountLabel: "Trabalho", from: "Exemplo <ex@example.com>", subject: "Assunto \(id)",
      unread: unread, date: "2026-11-04T12:00:00.000Z", messageId: "<\(id)@example.com>", references: [], labels: [],
      mailbox: .inbox, folder: "INBOX")
  }

  static func event(_ date: String, _ time: String, _ title: String) -> AgendaItem {
    AgendaItem(account: "cal-1", accountLabel: "Pessoal", date: date, time: time, title: title)
  }

  static func issue(_ key: String, awaitingApproval: Bool) -> JiraItem {
    JiraItem(
      key: key, summary: "Resumo \(key)", status: "Em andamento", statusCategory: .indeterminate, project: "DW",
      url: "https://jira.example.com/browse/\(key)", parent: nil, role: .assignee, awaitingApproval: awaitingApproval,
      kind: "Story", subtask: false, hierarchyLevel: 0, updatedAt: "2026-11-03T10:00:00.000Z", dueDate: "",
      priority: nil, flag: .none)
  }

  static func pull(_ number: Int) -> PullRequestItem {
    PullRequestItem(
      id: "pr-\(number)", repo: "acme/web", number: number, title: "PR \(number)",
      url: "https://github.com/acme/web/pull/\(number)", author: "bruno", draft: false, awaitingYou: true, mine: false,
      isPullRequest: true, updatedAt: "2026-11-04T10:00:00.000Z", createdAt: "2026-11-03T10:00:00.000Z", ci: .passing,
      failedChecks: [], review: .pending, pendingReviewers: [], reviewers: [], reviewRequestedAt: nil, merge: .clean,
      size: nil, headRef: nil, baseRef: nil, headSha: nil)
  }

  static func message(_ id: String) -> SlackMessage {
    SlackMessage(
      id: id, channel: "geral", author: "carla", text: "Mensagem \(id)", date: "2026-11-04T11:00:00.000Z",
      url: "https://example.slack.com/\(id)")
  }

  /// Every module on, each with something to count.
  static var full: DashboardState {
    DashboardState(
      updatedAt: "2026-11-04T16:00:00.000Z",
      modules: [.slack, .pulls, .jira, .agenda, .notes, .tasks, .email],
      email: PanelResult(
        data: [email("1", unread: true), email("2", unread: false), email("3", unread: true)], error: nil),
      agenda: PanelResult(
        data: [
          event("2026-11-04", "15:00", "Planejamento"),
          event("2026-11-04", "09:00", "Daily"),
          event("2026-11-04", "", "Aniversário"),
          event("2026-11-05", "10:00", "Amanhã"),
        ],
        error: nil),
      reviewRequests: PanelResult(
        data: ReviewRequestsDigest(items: [pull(7), pull(9)], truncated: false, total: 2, scopeNote: nil),
        error: nil),
      jira: PanelResult(
        data: [issue("DW-1", awaitingApproval: true), issue("DW-2", awaitingApproval: false)], error: nil),
      jiraProblems: PanelResult(
        data: [
          JiraProblemItem(item: issue("DW-3", awaitingApproval: false), problems: [.storyWithoutEpic]),
          JiraProblemItem(item: issue("DW-4", awaitingApproval: false), problems: [.epicWithoutStories]),
        ],
        error: nil),
      tasks: PanelResult(
        data: [
          task("today-low", due: "2026-11-04", priority: .low),
          task("late", due: "2026-11-01"),
          task("today-high", due: "2026-11-04", priority: .high),
          task("done-late", due: "2026-10-30", completed: true),
          task("tomorrow", due: "2026-11-05"),
          task("no-date", due: ""),
        ],
        error: nil),
      slack: PanelResult(
        data: SlackDigest(mentions: [message("m1")], directs: [message("d1"), message("d2")], team: "Acme"),
        error: nil)
    )
  }
}
