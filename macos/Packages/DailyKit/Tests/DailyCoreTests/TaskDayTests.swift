import DailyModels
import Foundation
import Testing

@testable import DailyCore

@Suite struct TaskDayTests {
  let now = Date(timeIntervalSince1970: 1_793_020_200)  // 2026-10-26T13:10:00Z

  @Test func isoDayAndMinuteAreGregorianWhateverTheCalendar() {
    var buddhist = Calendar(identifier: .buddhist)
    buddhist.timeZone = .gmt
    #expect(TaskDay.isoDay(now, calendar: buddhist) == "2026-10-26")
    #expect(TaskDay.minuteOfDay(now, calendar: buddhist) == "13:10")
  }

  @Test func onlyTheTimeZoneCounts() throws {
    let saoPaulo = TaskDay.gregorian(in: try #require(TimeZone(identifier: "America/Sao_Paulo")))
    let late = Date(timeIntervalSince1970: 1_793_070_600)  // 2026-10-27T03:10:00Z
    #expect(TaskDay.isoDay(late, calendar: saoPaulo) == "2026-10-27")
    #expect(TaskDay.isoDay(late.addingTimeInterval(-3600), calendar: saoPaulo) == "2026-10-26")
  }

  @Test func addDaysCrossesMonthsAndYears() {
    #expect(TaskDay.addDays("2026-12-30", 3) == "2027-01-02")
    #expect(TaskDay.addDays("2026-03-01", -1) == "2026-02-28")
    #expect(TaskDay.addDays("bad", 1) == "bad")
  }
}
