import DailyModels
import Foundation
import Testing

@testable import FeatureHome

/// Mirrors `tests/components/NowBand.test.tsx` and `greetingName` in `lib/greeting.ts`.
@Suite struct GreetingTests {
  func user(fullName: String?, username: String = "phil") -> CurrentUser {
    CurrentUser(username: username, isAdmin: false, avatarUrl: nil, fullName: fullName, email: nil)
  }

  @Test func greetsByFirstNameAndWelcomesAFirstVisit() {
    let greeting = Greeting(user: user(fullName: "Philippe Exemplo"), welcome: .first)
    #expect(greeting.heading == "Olá, Philippe")
    #expect(greeting.welcome == "Bem-vindo")
  }

  @Test func welcomesAReturningPersonBack() {
    #expect(Greeting(user: user(fullName: "Ana"), welcome: .returning).welcome == "Bem-vindo de volta")
  }

  @Test func stillGreetsWhenNoOneIsKnown() {
    #expect(Greeting(user: nil, welcome: .first).heading == "Olá")
  }

  @Test(arguments: [
    (String?.none, "phil"),
    ("", "phil"),
    ("   ", "phil"),
    ("  Ana   Souza ", "Ana"),
    ("Bruno", "Bruno"),
  ])
  func nameFallsBackToTheUsername(fullName: String?, expected: String) {
    #expect(Greeting.greetingName(fullName: fullName, username: "phil") == expected)
  }
}

/// `components/Clock.tsx`.
@Suite struct ClockTextTests {
  @Test func formatsTimeWithSeconds() {
    #expect(ClockText.time(Fixtures.now, calendar: Fixtures.calendar) == "13:15:07")
  }

  @Test func formatsWeekdayDayAndMonthInPortuguese() {
    #expect(ClockText.date(Fixtures.now, calendar: Fixtures.calendar) == "quarta-feira, 4 de novembro")
  }

  @Test func padsMidnight() throws {
    let midnight = try #require(
      Fixtures.calendar.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 0, minute: 0, second: 5)))
    #expect(ClockText.time(midnight, calendar: Fixtures.calendar) == "00:00:05")
    #expect(ClockText.date(midnight, calendar: Fixtures.calendar) == "domingo, 1 de março")
    #expect(ClockText.isoDay(midnight, calendar: Fixtures.calendar) == "2026-03-01")
  }
}
