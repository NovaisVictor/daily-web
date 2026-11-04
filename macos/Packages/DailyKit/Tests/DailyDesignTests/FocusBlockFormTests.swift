import Foundation
import Testing

@testable import DailyDesign

/// `defaultStart` cases from `tests/lib/focusBlock.test.ts`.
@Suite struct FocusBlockFormTests {
  nonisolated static let saoPaulo: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo") ?? .gmt
    return calendar
  }()

  nonisolated static func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    let components = DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute)
    guard let date = saoPaulo.date(from: components) else {
      Issue.record("Invalid test date \(components)")
      return .distantPast
    }
    return date
  }

  @Test(arguments: [
    (at(21, 10, 7), at(21, 10, 30)),
    (at(21, 10, 20), at(21, 10, 30)),
    (at(21, 10, 25), at(21, 11)),
    (at(21, 19, 50), at(21, 20)),
    (at(21, 20, 10), at(22, 9)),
    // Rolling past midnight lands on 00:00, as on the web (no 20:00 check applies).
    (at(21, 23, 45), at(22, 0)),
  ])
  func roundsTheDefaultStart(now: Date, expected: Date) {
    #expect(FocusBlockForm.defaultStart(now: now, calendar: Self.saoPaulo) == expected)
  }
}
