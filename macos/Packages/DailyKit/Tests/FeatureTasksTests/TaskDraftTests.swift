import DailyModels
import Foundation
import Testing

@testable import FeatureTasks

@Suite struct TaskDraftTests {
  @Test func opensAStoredDateAndTimeAsText() {
    let draft = TaskDraft(task: makeTask(due: "2026-11-05", time: "14:30", recur: "absoluteMonthly"))
    #expect(draft.day == "2026-11-05")
    #expect(draft.time == "14:30")
    #expect(draft.due == "2026-11-05 14:30")
    #expect(draft.recur == .monthly)
  }

  @Test func distrustsDatesOfAnotherShape() {
    let draft = TaskDraft(task: makeTask(due: "amanhã", time: "14:30", recur: "daily"))
    #expect(draft.due.isEmpty)
    #expect(draft.time.isEmpty)
    #expect(draft.recur == .none)
  }

  @Test func recurrenceNeedsADate() {
    var draft = TaskDraft(task: nil)
    draft.recur = .weekly
    #expect(draft.effectiveRecur == .none)
    draft.setDay("2026-11-06")
    #expect(draft.effectiveRecur == .weekly)
  }

  @Test func createBodyLeavesOutWhatIsNotSet() {
    var draft = TaskDraft(task: nil)
    draft.title = "  Comprar café "
    let plain = FakeAPIClient.encode(draft.createBody)
    #expect(plain == #"{"due":"","priority":"normal","title":"Comprar café"}"#)

    draft.setDay("2026-11-06")
    draft.setTime("14:30")
    draft.recur = .daily
    draft.priority = .high
    draft.column = .doing
    let full = FakeAPIClient.encode(draft.createBody)
    #expect(
      full == #"{"due":"2026-11-06 14:30","priority":"high","recur":"daily","status":"doing","title":"Comprar café"}"#)
  }

  @Test func editBodySendsEveryField() {
    var draft = TaskDraft(task: makeTask(title: "Antigo", due: "2026-11-05", recur: "weekly"))
    draft.title = "Novo"
    draft.setDay(nil)
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
    draft.setTime("08:00")
    #expect(draft.isDirty(comparedTo: initial))
    #expect(!draft.styleChanged(from: initial))
    // Typed text that does not parse changes no date, but closing would lose it.
    draft = initial
    draft.setTyped("ontem", now: Date())
    #expect(draft.due == initial.due)
    #expect(draft.isDirty(comparedTo: initial))
  }

  @Test func quickDayKeepsTheTimeAndNoDayDropsIt() {
    var draft = TaskDraft(task: nil)
    draft.setTime("09:15")
    #expect(draft.time.isEmpty, "a time needs a day")
    draft.setDay("2026-11-09")
    draft.setTime("09:15")
    draft.setDay("2026-11-10")
    #expect(draft.due == "2026-11-10 09:15")
    draft.setDay(nil)
    #expect(draft.due.isEmpty)
    #expect(draft.time.isEmpty)
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
    #expect(TaskDraft.clipped(String(repeating: "a", count: 300)).utf16.count == TaskDraft.titleLimit)
  }

  /// A cut is said under the field until the person edits the text again.
  @Test func limitHintShowsOnlyWhileTheTextIsWhatTheCutLeft() {
    let cut = TaskDraft.clipped(String(repeating: "a", count: 300))
    #expect(TaskDraft.showsLimitHint(title: cut, cutTitle: cut))
    #expect(!TaskDraft.showsLimitHint(title: String(cut.dropLast()), cutTitle: cut))
    #expect(!TaskDraft.showsLimitHint(title: String(repeating: "a", count: 255), cutTitle: nil))
    #expect(!TaskDraft.showsLimitHint(title: "", cutTitle: nil))
  }

  /// The quick-add field clips with the same rule: counted in UTF-16 as the
  /// browser does, and never half an emoji. Cutting 255 characters instead
  /// would keep up to twice the limit in UTF-16.
  @Test func clippingCountsUTF16AndKeepsWholeEmoji() {
    let emoji = String(repeating: "😀", count: 200)
    let clipped = TaskDraft.clipped(emoji)
    #expect(clipped.utf16.count == 254)
    #expect(clipped.count == 127)
    #expect(clipped.unicodeScalars.allSatisfy { $0 == "😀" })

    let mixed = String(repeating: "a", count: 254) + "😀"
    #expect(TaskDraft.clipped(mixed) == String(repeating: "a", count: 254))
    #expect(TaskDraft.clipped("curta") == "curta")
  }
}
