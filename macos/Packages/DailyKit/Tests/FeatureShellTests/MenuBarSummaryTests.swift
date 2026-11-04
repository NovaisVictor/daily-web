import DailyCore
import DailyModels
import Foundation
import Testing

@testable import FeatureShell

private func task(_ id: String, due: String, completed: Bool = false, priority: TaskPriority = .normal) -> TodoTask {
  TodoTask(
    id: id, title: "Tarefa \(id)", completed: completed, due: due, priority: priority, time: "", recur: "",
    notes: "", subtasks: [], doing: false, paper: nil, pin: nil, pinShape: nil)
}

private func event(_ date: String, _ time: String, _ title: String) -> AgendaItem {
  AgendaItem(account: "cal", accountLabel: "Agenda", date: date, time: time, title: title)
}

private var utc: Calendar {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = .gmt
  return calendar
}

/// 2026-11-04 13:05 UTC.
private let now = Date(timeIntervalSince1970: 1_793_797_500)

@Suite struct MenuBarSummaryTests {
  @Test func tasksAreLateThenTodayByPriorityAndCappedAtFive() {
    let items = [
      task("future", due: "2026-11-05"),
      task("done", due: "2026-11-01", completed: true),
      task("nodate", due: ""),
      task("today-low", due: "2026-11-04", priority: .low),
      task("today-high", due: "2026-11-04", priority: .high),
      task("late-2", due: "2026-11-02"),
      task("late-1", due: "2026-11-01"),
      task("late-3", due: "2026-11-03"),
      task("late-3b", due: "2026-11-03", priority: .high),
    ]
    let result = MenuBarSummary.tasks(items, today: "2026-11-04")
    #expect(result.map(\.id) == ["late-1", "late-2", "late-3b", "late-3", "today-high"])
    #expect(result.map(\.isOverdue) == [true, true, true, true, false])
  }

  @Test func eventsAreTodaysStillAheadWithAllDayFirst() {
    let items = [
      event("2026-11-04", "09:00", "Já passou"),
      event("2026-11-04", "15:00", "Depois"),
      event("2026-11-04", "", ""),
      event("2026-11-05", "10:00", "Amanhã"),
      event("2026-11-04", "13:05", "Agora"),
    ]
    let result = MenuBarSummary.events(items, today: "2026-11-04", minute: "13:05")
    #expect(result.map(\.time) == ["dia", "13:05", "15:00"])
    #expect(result.map(\.title) == ["—", "Agora", "Depois"])
  }

  @Test func readsTheStateWithTheLocalDay() {
    var state = PreviewFixtures.dashboard
    state.modules = [.agenda, .tasks]
    state.tasks = PanelResult(data: [task("a", due: "2026-11-04")], error: nil)
    state.agenda = PanelResult(data: [event("2026-11-04", "14:30", "Reunião")], error: nil)
    state.notifications = PanelResult(
      data: [
        NotificationItem(id: "slack:1", source: .slack, title: "a", url: "", read: false, date: ""),
        NotificationItem(id: "slack:2", source: .slack, title: "b", url: "", read: true, date: ""),
      ],
      error: nil)
    let summary = MenuBarSummary(state: state, now: now, calendar: utc)
    #expect(summary.tasks?.map(\.id) == ["a"])
    #expect(summary.events?.map(\.title) == ["Reunião"])
    #expect(summary.unreadNotifications == 1)
  }

  @Test func switchedOffModulesShowNothingAndErrorsPassThrough() {
    var state = PreviewFixtures.dashboard
    state.modules = [.tasks]
    state.tasks = PanelResult(data: nil, error: "Falha ao carregar tarefas")
    let summary = MenuBarSummary(state: state, now: now, calendar: utc)
    #expect(summary.events == nil)
    #expect(summary.agendaError == nil)
    #expect(summary.tasks == nil)
    #expect(summary.tasksError == "Falha ao carregar tarefas")
  }
}
