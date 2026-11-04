import DailyModels
import Foundation
import Testing

@testable import FeatureTasks

@Suite struct TaskDraftTests {
  @Test func opensAStoredDateAndTimeAsText() {
    let draft = TaskDraft(task: makeTask(due: "2026-11-05", time: "14:30", recur: "absoluteMonthly"))
    #expect(draft.dueText == "2026-11-05 14:30")
    #expect(draft.recur == .monthly)
  }

  @Test func distrustsDatesOfAnotherShape() {
    let draft = TaskDraft(task: makeTask(due: "amanhã", time: "14:30", recur: "daily"))
    #expect(draft.dueText.isEmpty)
    #expect(draft.recur == .none)
  }

  @Test func recurrenceNeedsADate() {
    var draft = TaskDraft(task: nil)
    draft.recur = .weekly
    #expect(draft.effectiveRecur == .none)
    draft.dueText = "amanhã"
    #expect(draft.effectiveRecur == .weekly)
  }

  @Test func createBodyLeavesOutWhatIsNotSet() {
    var draft = TaskDraft(task: nil)
    draft.title = "  Comprar café "
    let plain = FakeAPIClient.encode(draft.createBody)
    #expect(plain == #"{"due":"","priority":"normal","title":"Comprar café"}"#)

    draft.dueText = "amanhã 14:30"
    draft.recur = .daily
    draft.priority = .high
    draft.column = .doing
    let full = FakeAPIClient.encode(draft.createBody)
    #expect(
      full == #"{"due":"amanhã 14:30","priority":"high","recur":"daily","status":"doing","title":"Comprar café"}"#)
  }

  @Test func editBodySendsEveryField() {
    var draft = TaskDraft(task: makeTask(title: "Antigo", due: "2026-11-05", recur: "weekly"))
    draft.title = "Novo"
    draft.dueText = ""
    #expect(FakeAPIClient.encode(draft.editBody) == #"{"due":"","priority":"normal","recur":"none","title":"Novo"}"#)
  }

  @Test func dirtyTracksEveryField() {
    let initial = TaskDraft(task: makeTask(due: "2026-11-05"))
    var draft = initial
    #expect(!draft.isDirty(comparedTo: initial))
    draft.pin = .green
    #expect(draft.isDirty(comparedTo: initial))
    #expect(draft.styleChanged(from: initial))
    draft = initial
    draft.dueText = "hoje"
    #expect(draft.isDirty(comparedTo: initial))
    #expect(!draft.styleChanged(from: initial))
  }

  @Test func quickDayKeepsTheTypedTime() {
    var draft = TaskDraft(task: nil)
    draft.dueText = "amanhã 09:15"
    draft.setDay("2026-11-10")
    #expect(draft.dueText == "2026-11-10 09:15")
    #expect(draft.dayPart == "2026-11-10")
    draft.setDay(nil)
    #expect(draft.dueText.isEmpty)
  }

  @Test func nextWeekIsTheComingMonday() throws {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = .gmt
    // Friday 2026-11-06.
    let friday = try #require(utc.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 10)))
    let days = TaskDraft.quickDays(now: friday, calendar: utc)
    #expect(days.today == "2026-11-06")
    #expect(days.tomorrow == "2026-11-07")
    #expect(days.monday == "2026-11-09")
    // On a Monday it is the one after.
    let monday = try #require(utc.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 10)))
    #expect(TaskDraft.quickDays(now: monday, calendar: utc).monday == "2026-11-16")
  }

  @Test func titleIsClippedToTheBrowserLimit() {
    var draft = TaskDraft(task: nil)
    draft.title = String(repeating: "a", count: 300)
    draft.clipTitle()
    #expect(draft.title.utf16.count == TaskDraft.titleLimit)
  }
}
