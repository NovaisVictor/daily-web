import DailyCore
import DailyModels
import Foundation
import Testing

@testable import FeatureAgenda

nonisolated let saoPaulo: Calendar = {
  var calendar = Calendar(identifier: .gregorian)
  guard let zone = TimeZone(identifier: "America/Sao_Paulo") else {
    preconditionFailure("Missing time zone")
  }
  calendar.timeZone = zone
  return calendar
}()

nonisolated func localDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
  guard let date = saoPaulo.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))
  else { preconditionFailure("Invalid test date") }
  return date
}

nonisolated func event(_ date: String, _ time: String, _ title: String, account: String = "cal-1") -> AgendaItem {
  AgendaItem(
    account: account, accountLabel: account == "cal-1" ? "Trabalho" : "Pessoal", date: date, time: time,
    title: title)
}

@Suite struct AgendaRangeTests {
  @Test func offersTheWebPeriodsInOrder() {
    #expect(AgendaRange.all.map(\.label) == ["Hoje", "Hoje e amanhã", "3 dias", "7 dias", "14 dias"])
    #expect(AgendaRange.all.map(\.days) == PreferencesStore.agendaRanges)
  }

  // The empty state must match the chosen period (`AgendaPanel.test.tsx`).
  @Test(arguments: [
    (1, "Nada agendado para hoje."),
    (2, "Nada agendado para hoje e amanhã."),
    (7, "Nada agendado nos próximos 7 dias."),
    (14, "Nada agendado nos próximos 14 dias."),
    (5, "Nada agendado para hoje e amanhã."),
  ])
  func describesThePeriodWhenEmpty(days: Int, text: String) {
    #expect(AgendaRange.emptyText(days: days) == text)
  }
}

@Suite struct AgendaGroupingTests {
  @Test func groupsByDayInDateAndTimeOrder() {
    let groups = AgendaLogic.group([
      event("2026-08-27", "09:00", "C"),
      event("2026-08-26", "14:00", "B"),
      event("2026-08-26", "", "Dia todo"),
      event("2026-08-26", "08:00", "A"),
    ])
    #expect(groups.map(\.date) == ["2026-08-26", "2026-08-27"])
    #expect(groups[0].items.map(\.title) == ["Dia todo", "A", "B"])
    #expect(groups[1].items.map(\.title) == ["C"])
  }

  @Test func keepsTheServerOrderForTies() {
    let groups = AgendaLogic.group([event("2026-08-26", "10:00", "primeiro"), event("2026-08-26", "10:00", "segundo")])
    #expect(groups[0].items.map(\.title) == ["primeiro", "segundo"])
  }

  @Test func showsAccountLabelsOnlyWithSeveralCalendars() {
    #expect(!AgendaLogic.showsAccountLabels([event("2026-08-26", "10:00", "a"), event("2026-08-26", "11:00", "b")]))
    #expect(
      AgendaLogic.showsAccountLabels([
        event("2026-08-26", "10:00", "a"), event("2026-08-26", "11:00", "b", account: "cal-2"),
      ]))
  }

  // The web's cases (`AgendaPanel.test.tsx`, `relativeDayLabel`).
  @Test(arguments: [
    ("2026-08-25", "hoje"),
    ("2026-08-26", "amanhã"),
    ("2026-08-29", "sábado, 29 de agosto"),
    ("2026-09-01", "terça, 1 de setembro"),
    ("lixo", "lixo"),
  ])
  func labelsTheDay(iso: String, label: String) {
    #expect(AgendaLogic.relativeDayLabel(iso, today: localDate(2026, 8, 25, 15), calendar: saoPaulo) == label)
  }
}

@Suite struct FocusDropTests {
  @Test func acceptsAValidSourceTrimmed() {
    let source = FocusSource(kind: .jira, ref: " DEV-1 ", title: " Corrigir ", url: "https://jira.exemplo/DEV-1")
    #expect(
      AgendaLogic.acceptedSource([source])
        == FocusSource(kind: .jira, ref: "DEV-1", title: "Corrigir", url: "https://jira.exemplo/DEV-1"))
  }

  // `parseFocusSource` refusals from `tests/lib/focusBlock.test.ts`.
  @Test(arguments: [
    FocusSource(kind: .task, ref: String(repeating: "x", count: 65), title: "X"),
    FocusSource(kind: .task, ref: "1", title: String(repeating: "x", count: 201)),
    FocusSource(kind: .task, ref: "1", title: "   "),
    FocusSource(kind: .pull, ref: "1", title: "X", url: "http://exemplo.com"),
    FocusSource(kind: .pull, ref: "1", title: "X", url: "não é url"),
  ])
  func refusesInvalidSources(source: FocusSource) {
    #expect(AgendaLogic.acceptedSource([source]) == nil)
  }

  @Test func aNonGregorianSystemCalendarStillMatchesTheServersDates() throws {
    var buddhist = Calendar(identifier: .buddhist)
    buddhist.timeZone = saoPaulo.timeZone
    let today = localDate(2026, 8, 25, 15)
    #expect(AgendaLogic.localDateString(today, calendar: buddhist) == "2026-08-25")
    #expect(AgendaLogic.relativeDayLabel("2026-08-25", today: today, calendar: buddhist) == "hoje")
    #expect(AgendaLogic.relativeDayLabel("2026-08-26", today: today, calendar: buddhist) == "amanhã")
    var japanese = Calendar(identifier: .japanese)
    japanese.timeZone = saoPaulo.timeZone
    #expect(AgendaLogic.relativeDayLabel("2026-08-28", today: today, calendar: japanese) == "sexta, 28 de agosto")
  }

  @Test func takesTheFirstValidOfSeveral() {
    let bad = FocusSource(kind: .task, ref: "1", title: "")
    let good = FocusSource(kind: .task, ref: "2", title: "Escrever relatório")
    #expect(AgendaLogic.acceptedSource([bad, good]) == good)
  }
}
