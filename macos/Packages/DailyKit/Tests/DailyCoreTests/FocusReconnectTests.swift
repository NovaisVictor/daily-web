import DailyAPI
import DailyModels
import Foundation
import Testing

@testable import DailyCore

@Suite struct FocusReconnectTests {
  let server: URL = {
    guard let url = URL(string: "https://daily.example.com") else { preconditionFailure("Invalid test URL") }
    return url
  }()
  let personal = AgendaCalendarRef(id: "conn-google", label: "Pessoal", account: "voce@example.com", canWrite: true)
  let holidays = AgendaCalendarRef(id: "conn-ics", label: "Feriados", account: "", canWrite: false)
  let source = FocusSource(kind: .jira, ref: "DEMO-1", title: "Ajustar filtro")

  @Test func buildsTheStartURLWithTheLoginHint() {
    #expect(
      FocusReconnect.url(server: server, account: "voce@example.com")?.absoluteString
        == "https://daily.example.com/api/integrations/agenda/google/start?login_hint=voce@example.com")
  }

  @Test func anEmptyOrMissingAccountSendsNoHint() {
    let bare = "https://daily.example.com/api/integrations/agenda/google/start"
    #expect(FocusReconnect.url(server: server, account: "")?.absoluteString == bare)
    #expect(FocusReconnect.url(server: server, account: nil)?.absoluteString == bare)
  }

  @Test func replacesTheServersPathAndQuery() throws {
    let nested = try #require(URL(string: "https://daily.example.com/settings?tab=1#x"))
    #expect(
      FocusReconnect.url(server: nested, account: "a@b.c")?.absoluteString
        == "https://daily.example.com/api/integrations/agenda/google/start?login_hint=a@b.c")
  }

  @Test func aPlusInTheAccountSurvivesTheServersParsing() throws {
    let url = try #require(FocusReconnect.url(server: server, account: "voce+daily@example.com"))
    #expect(url.query == "login_hint=voce%2Bdaily@example.com")
  }

  @Test func reconnectsTheChosenCalendarElseTheFirst() {
    let calendars = [holidays, personal]
    #expect(FocusReconnect.calendar(for: "conn-google", in: calendars) == personal)
    #expect(FocusReconnect.calendar(for: "gone", in: calendars) == holidays)
    #expect(FocusReconnect.calendar(for: "x", in: []) == nil)
    #expect(FocusReconnect.accountName(personal) == "voce@example.com")
    #expect(FocusReconnect.accountName(holidays) == "Feriados")
  }

  @Test func theBookingNamesTheAccountOnlyWithAServer() {
    let booking = FocusBooking(source: source, calendars: [holidays, personal], server: server)
    #expect(booking.writableCalendars == [personal])
    #expect(booking.reconnectAccount(for: "conn-google") == "voce@example.com")
    #expect(booking.reconnectAccount(for: "conn-ics") == "Feriados")
    let offline = FocusBooking(source: source, calendars: [personal], server: nil)
    #expect(offline.reconnectAccount(for: "conn-google") == nil)
    #expect(offline.reconnectURL(for: "conn-google") == nil)
  }

  @Test func theBookingShowsEachOutcome() async {
    let booking = FocusBooking(source: source, calendars: [personal], server: server)
    let start = Date(timeIntervalSince1970: 1_790_000_000)
    var seen: [String] = []
    let refused = await booking.save(start: start, minutes: 50, connectionId: "conn-google") { source, id, _, minutes in
      seen.append("\(source.ref) \(id) \(minutes)")
      return .reconnect("reconecte o Google")
    }
    #expect(!refused)
    #expect(seen == ["DEMO-1 conn-google 50"])
    #expect(booking.reconnectMessage == "reconecte o Google")
    #expect(!booking.isSaving)

    let failed = await booking.save(start: start, minutes: 50, connectionId: "conn-google") { _, _, _, _ in
      .failed(.server(status: 500, message: "boom", code: nil, retry: nil))
    }
    #expect(!failed)
    #expect(booking.reconnectMessage == nil)
    #expect(booking.errorMessage != nil)

    let item = AgendaItem(
      account: "conn-google", accountLabel: "Pessoal", date: "2026-10-01", time: "10:00", title: "x")
    let created = await booking.save(start: start, minutes: 25, connectionId: "conn-google") { _, _, _, _ in
      .created(item)
    }
    #expect(created)
    #expect(booking.errorMessage == nil)
  }
}
