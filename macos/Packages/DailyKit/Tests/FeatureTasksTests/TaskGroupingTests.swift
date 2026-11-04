import DailyModels
import Foundation
import Testing

@testable import FeatureTasks

/// Ported from `tests/lib/taskGrouping.test.ts`.
@Suite struct TaskGroupingTests {
  /// `new Date('2026-08-25T12:00:00Z')` read in UTC, as the web suite runs.
  private let today = Date(timeIntervalSince1970: 1_787_659_200)
  private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
  }

  @Test func splitsIntoWindowsInOrder() {
    let tasks = [
      makeTask("a", due: "2026-08-20"),
      makeTask("b", due: "2026-08-25"),
      makeTask("c", due: "2026-08-28"),
      makeTask("d", due: "2026-09-15"),
      makeTask("e", due: "2026-12-01"),
      makeTask("f", due: ""),
    ]
    let groups = TaskGrouping.group(tasks, today: today, calendar: utc)
    #expect(groups.map(\.key) == [.overdue, .today, .week, .month, .later, .noDate])
  }

  @Test func omitsEmptyWindows() {
    let groups = TaskGrouping.group([makeTask(due: "2026-08-25")], today: today, calendar: utc)
    #expect(groups.count == 1)
    #expect(groups.first?.key == .today)
    #expect(groups.first?.label == "HOJE")
  }

  @Test func sortsByDueThenPriorityWithCompletedLast() {
    let tasks = [
      makeTask("low", due: "2026-08-25", priority: .low),
      makeTask("high", due: "2026-08-25", priority: .high),
      makeTask("done", completed: true, due: "2026-08-25", priority: .high),
    ]
    let groups = TaskGrouping.group(tasks, today: today, calendar: utc)
    #expect(groups.first?.tasks.map(\.id) == ["high", "low", "done"])
  }

  @Test func undatedGoesToNoDateEvenWhenCompleted() {
    let groups = TaskGrouping.group([makeTask(completed: true)], today: today, calendar: utc)
    #expect(groups.first?.key == .noDate)
  }

  @Test func lateEveningInANegativeOffsetIsStillToday() throws {
    var saoPaulo = Calendar(identifier: .gregorian)
    saoPaulo.timeZone = try #require(TimeZone(identifier: "America/Sao_Paulo"))
    // 2026-08-25 22:00 in São Paulo is already the 26th in UTC.
    let lateEvening = Date(timeIntervalSince1970: 1_787_706_000)
    let groups = TaskGrouping.group([makeTask("1", due: "2026-08-25")], today: lateEvening, calendar: saoPaulo)
    #expect(groups.first { $0.key == .today }?.tasks.map(\.id) == ["1"])
    #expect(groups.first { $0.key == .overdue } == nil)
  }

  @Test func windowEdgesAreSixAndTwentyNineDaysAhead() {
    let tasks = [
      makeTask("w", due: "2026-08-31"),
      makeTask("m", due: "2026-09-01"),
      makeTask("m2", due: "2026-09-23"),
      makeTask("l", due: "2026-09-24"),
    ]
    let groups = TaskGrouping.group(tasks, today: today, calendar: utc)
    #expect(groups.map(\.key) == [.week, .month, .later])
    #expect(groups[1].tasks.map(\.id) == ["m", "m2"])
  }

  @Test func overdueIsOpenWithAPastDate() {
    #expect(TaskGrouping.isOverdue(makeTask(due: "2026-08-24"), today: today, calendar: utc))
    #expect(!TaskGrouping.isOverdue(makeTask(due: "2026-08-25"), today: today, calendar: utc))
    #expect(!TaskGrouping.isOverdue(makeTask(completed: true, due: "2026-08-01"), today: today, calendar: utc))
    #expect(!TaskGrouping.isOverdue(makeTask(), today: today, calendar: utc))
  }

  @Test func addDaysCrossesMonthAndYear() {
    #expect(TaskGrouping.addDays("2026-08-25", 6) == "2026-08-31")
    #expect(TaskGrouping.addDays("2026-12-30", 3) == "2027-01-02")
    #expect(TaskGrouping.addDays("2026-03-01", -1) == "2026-02-28")
  }

  @Test func textHelpersMatchTheWeb() {
    #expect(TaskText.formatDue("2026-11-05", time: "") == "05/11")
    #expect(TaskText.formatDue("2026-11-05", time: "14:30") == "05/11 14:30")
    #expect(TaskText.formatDue("amanhã", time: "") == "amanhã")
    #expect(TaskGroupKey.month.chipLabel == "Este mês")
    #expect(TaskGroupKey.noDate.chipLabel == "Sem data")
    #expect(TaskText.matches("Revisão do relatório", query: " revisao "))
    #expect(TaskText.matches("qualquer", query: ""))
    #expect(!TaskText.matches("Revisão", query: "daily"))
  }
}
