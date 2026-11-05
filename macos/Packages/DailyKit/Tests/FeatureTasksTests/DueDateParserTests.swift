import Foundation
import Testing

@testable import FeatureTasks

/// `tests/lib/dateParsing.test.ts`, case by case.
@Suite struct DueDateParserTests {
  static func calendar(_ zone: String) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
    return calendar
  }

  let utc = calendar("UTC")
  let now = ISO8601DateFormatter().date(from: "2026-08-25T12:00:00Z") ?? .distantPast

  func parse(_ text: String) throws(DueParseError) -> ParsedDue {
    try DueDateParser.parse(text, now: now, calendar: utc)
  }

  func message(_ text: String) -> String? {
    do {
      _ = try parse(text)
      return nil
    } catch {
      return error.message
    }
  }

  @Test func emptyClearsDateAndTime() throws {
    #expect(try parse("") == ParsedDue(due: "none", time: "none"))
  }

  @Test func today() throws {
    #expect(try parse("hoje") == ParsedDue(due: "2026-08-25", time: "none"))
  }

  @Test func tomorrowWithAndWithoutAccent() throws {
    #expect(try parse("amanhã").due == "2026-08-26")
    #expect(try parse("amanha").due == "2026-08-26")
  }

  @Test func relativeDays() throws {
    #expect(try parse("+3d").due == "2026-08-28")
  }

  @Test func isoDay() throws {
    #expect(try parse("2026-09-01").due == "2026-09-01")
  }

  @Test func optionalTimeAtTheEnd() throws {
    #expect(try parse("hoje 14:30") == ParsedDue(due: "2026-08-25", time: "14:30"))
    #expect(try parse("2026-08-20 09:00") == ParsedDue(due: "2026-08-20", time: "09:00"))
  }

  @Test func refusesUnparseableDate() {
    #expect(message("32/13")?.hasPrefix("data inválida") == true)
  }

  @Test func refusesCalendarInvalidDate() {
    #expect(message("2026-02-30")?.hasPrefix("data inválida") == true)
  }

  @Test func refusesUnparseableTime() {
    #expect(message("hoje 25:00")?.hasPrefix("hora inválida") == true)
  }

  @Test func todayFollowsTheLocalDay() throws {
    let saoPaulo = Self.calendar("America/Sao_Paulo")
    let lateLocal = try #require(ISO8601DateFormatter().date(from: "2026-08-26T02:30:00Z"))
    #expect(
      try DueDateParser.parse("hoje", now: lateLocal, calendar: saoPaulo) == ParsedDue(due: "2026-08-25", time: "none"))
  }

  /// A Buddhist system calendar numbers 2026 as 2569; the server's days are Gregorian.
  @Test func buddhistSystemCalendarStillWritesGregorianDays() throws {
    var buddhist = Calendar(identifier: .buddhist)
    buddhist.timeZone = .gmt
    #expect(try DueDateParser.parse("hoje", now: now, calendar: buddhist).due == "2026-08-25")
    #expect(try DueDateParser.parse("+3d", now: now, calendar: buddhist).due == "2026-08-28")
    #expect(DueDateParser.preview("2026-08-30", now: now, calendar: buddhist) == "dom, 30/08")
    #expect(TaskDraft.quickDays(now: now, calendar: buddhist).today == "2026-08-25")
  }

  @Test func refusesNonASCIIDigits() {
    // Arabic-Indic digits match `\d` but are not what the server reads.
    #expect(message("٢٠٢٦-٠٨-٢٥")?.hasPrefix("data inválida") == true)
    #expect(message("hoje ١٤:٣٠")?.hasPrefix("hora inválida") == true)
  }

  // MARK: - Preview (`describeDue`, `TaskFormModal.tsx`)

  @Test func previewNamesTheWeekday() {
    #expect(DueDateParser.preview("amanhã 14:30", now: now, calendar: utc) == "qua, 26/08 14:30")
    #expect(DueDateParser.preview("2026-08-30", now: now, calendar: utc) == "dom, 30/08")
    #expect(DueDateParser.preview("ontem", now: now, calendar: utc) == nil)
    #expect(DueDateParser.preview("  ", now: now, calendar: utc) == nil)
  }

  @Test func typedHintShowsPreviewErrorOrExamples() {
    var draft = TaskDraft(task: nil)
    #expect(
      draft.typedHint(now: now, calendar: utc).text == "hoje, amanhã, +3d ou AAAA-MM-DD, com hora opcional no fim")
    draft.setTyped("+3d", now: now, calendar: utc)
    #expect(draft.typedHint(now: now, calendar: utc) == ("→ sex, 28/08", false))
    #expect(!draft.typedIsInvalid(now: now, calendar: utc))
    draft.setTyped("ontem", now: now, calendar: utc)
    let hint = draft.typedHint(now: now, calendar: utc)
    #expect(hint.isError)
    #expect(hint.text == "Não reconheci \"ontem\". Exemplos: hoje, amanhã 14:30, +3d, 2026-11-05 09:00.")
    #expect(draft.typedIsInvalid(now: now, calendar: utc))
  }

  // MARK: - What is sent (SC-014-2, `TaskFormModal.tsx:224`)

  /// The web sends `day` or `day time`, parsed from the text, never the text.
  @Test(arguments: [
    ("hoje", "2026-08-25"),
    ("amanhã 14:30", "2026-08-26 14:30"),
    ("amanha", "2026-08-26"),
    ("+3d 09:00", "2026-08-28 09:00"),
    ("2026-11-05 09:00", "2026-11-05 09:00"),
    ("  2026-11-05  ", "2026-11-05"),
  ])
  func typedTextSendsTheParsedDue(text: String, sent: String) {
    var draft = TaskDraft(task: nil)
    draft.title = "X"
    draft.setTyped(text, now: now, calendar: utc)
    #expect(draft.createBody.due == sent)
    #expect(draft.editBody.due == sent)
  }

  /// While the text does not parse, the date it last stood for stays.
  @Test func unparsedTextKeepsTheLastDate() {
    var draft = TaskDraft(task: nil)
    draft.setTyped("amanhã 14:30", now: now, calendar: utc)
    draft.setTyped("amanhã 14:3", now: now, calendar: utc)
    #expect(draft.due == "2026-08-26 14:30")
    draft.clearTyped()
    #expect(draft.due == "2026-08-26 14:30")
    #expect(draft.typed.isEmpty)
  }

  @Test func timePickerNeedsADay() {
    var draft = TaskDraft(task: nil)
    draft.setTime("10:00")
    #expect(draft.due.isEmpty)
    draft.setTyped("amanhã", now: now, calendar: utc)
    draft.setTime("10:00")
    #expect(draft.due == "2026-08-26 10:00")
    draft.setTime(nil)
    #expect(draft.due == "2026-08-26")
  }
}
