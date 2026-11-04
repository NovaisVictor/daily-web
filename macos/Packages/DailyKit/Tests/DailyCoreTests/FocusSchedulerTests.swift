import DailyAPI
import DailyModels
import Foundation
import Testing

@testable import DailyCore

@Suite struct FocusSchedulerTests {
  let client = FakeAPIClient()
  let toasts: ToastCenter
  let dashboard: DashboardStore
  let scheduler: FocusScheduler
  let now = VirtualClock.origin
  let source = FocusSource(
    kind: .jira, ref: " DEMO-142 ", title: " Ajustar filtro ", url: "https://acme.atlassian.net/browse/DEMO-142")

  init() {
    toasts = quietToasts()
    dashboard = DashboardStore(client: client, cache: nil, toasts: toasts)
    let now = self.now
    scheduler = FocusScheduler(client: client, dashboard: dashboard, toasts: toasts, now: { now })
  }

  func agendaState(_ items: [AgendaItem]) -> DashboardState {
    DashboardState(updatedAt: "x", modules: [.agenda], agenda: PanelResult(data: items, error: nil))
  }

  func item(_ date: String, _ time: String, _ title: String) -> AgendaItem {
    AgendaItem(account: "conn-cal-1", accountLabel: "Agenda", date: date, time: time, title: title)
  }

  @Test(arguments: [
    (FocusSource(kind: .task, ref: "", title: "   ", url: nil), 50, "título inválido"),
    (FocusSource(kind: .task, ref: "", title: String(repeating: "a", count: 201), url: nil), 50, "título inválido"),
    (
      FocusSource(kind: .task, ref: String(repeating: "r", count: 65), title: "ok", url: nil), 50, "referência inválida"
    ),
    (
      FocusSource(kind: .pull, ref: "acme/api#77", title: "ok", url: "http://github.com/acme/api/pull/77"), 50,
      "URL inválida"
    ),
    (FocusSource(kind: .task, ref: "", title: "ok", url: nil), 30, "duração inválida"),
  ])
  func refusesWhatTheServerWould(source: FocusSource, minutes: Int, message: String) async {
    let result = await scheduler.schedule(
      source, connectionId: "conn-cal-1", start: now.addingTimeInterval(600), minutes: minutes)
    #expect(result == .invalid(message))
    #expect(client.calls.isEmpty)
  }

  @Test func refusesStartsOutsideTheWindow() async {
    let tooEarly = await scheduler.schedule(source, connectionId: "c", start: now.addingTimeInterval(-301), minutes: 25)
    let tooLate = await scheduler.schedule(
      source, connectionId: "c", start: now.addingTimeInterval(60 * 86400 + 1), minutes: 25)
    let missing = await scheduler.schedule(source, connectionId: "", start: now, minutes: 25)
    #expect(tooEarly == .invalid("início inválido"))
    #expect(tooLate == .invalid("início inválido"))
    #expect(missing == .invalid("conexão não informada"))
  }

  @Test func createsAndInsertsSorted() async {
    dashboard.apply(agendaState([item("2026-11-04", "09:00", "a"), item("2026-11-05", "", "c")]))
    let created = item("2026-11-04", "15:00", "🔒 DEMO-142 — Ajustar filtro")
    client.respond { _ in FakeAPIClient.json(FocusBlockResponse(item: created)) }

    let result = await scheduler.schedule(
      source, connectionId: "conn-cal-1", start: now.addingTimeInterval(3600), minutes: 50)

    #expect(result == .created(created))
    let body =
      #"{"connectionId":"conn-cal-1","item":{"kind":"jira","ref":"DEMO-142","title":"Ajustar filtro","#
      + #""url":"https:\/\/acme.atlassian.net\/browse\/DEMO-142"},"minutes":50,"start":"2026-10-26T08:33:20.000Z"}"#
    #expect(client.calls == [.init(method: "POST", path: "/api/agenda/focus-blocks", body: body)])
    #expect(dashboard.state?.agenda.data?.map(\.title) == ["a", "🔒 DEMO-142 — Ajustar filtro", "c"])
    #expect(toasts.toasts.map(\.text) == ["Bloco de foco criado"])
  }

  @Test func conflictAsksToReconnect() async {
    client.respond { _ throws(APIError) in
      throw .server(status: 409, message: "reconecte o Google para criar blocos de foco", code: nil, retry: nil)
    }
    let result = await scheduler.schedule(source, connectionId: "c", start: now, minutes: 25)
    #expect(result == .reconnect("reconecte o Google para criar blocos de foco"))
  }

  @Test func otherFailuresAreReturned() async {
    client.respond { _ throws(APIError) in throw .offline }
    let result = await scheduler.schedule(source, connectionId: "c", start: now, minutes: 25)
    #expect(result == .failed(.offline))
  }
}
