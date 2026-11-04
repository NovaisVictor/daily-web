import DailyAPI
import DailyCore
import DailyModels
import Foundation
import Testing

@testable import FeatureAgenda

@Suite struct AgendaStoreTests {
  let client = RecordingAPIClient()
  let dashboard: DashboardStore
  let preferences: PreferencesStore
  let focus: FocusScheduler
  let store: AgendaStore
  let now = localDate(2026, 9, 21, 10, 7)

  init() {
    let toasts = quietToasts()
    dashboard = DashboardStore(client: client, cache: nil, toasts: toasts)
    preferences = PreferencesStore(client: client, dashboard: dashboard, toasts: toasts, defaults: scratchDefaults())
    let now = self.now
    focus = FocusScheduler(client: client, dashboard: dashboard, toasts: toasts, now: { now })
    store = AgendaStore(dashboard: dashboard, preferences: preferences, focus: focus, now: { now }, calendar: saoPaulo)
  }

  func state(days: Int = 2, calendars: [AgendaCalendarRef] = [], items: [AgendaItem] = []) -> DashboardState {
    DashboardState(
      updatedAt: "x", modules: [.agenda], agendaDays: days, agendaCalendars: calendars,
      agenda: PanelResult(data: items, error: nil))
  }

  let readOnly = AgendaCalendarRef(id: "conn-ics", label: "Feriados", account: "", canWrite: false)
  let writable = AgendaCalendarRef(id: "conn-google", label: "Pessoal", account: "voce@example.com", canWrite: true)
  let source = FocusSource(kind: .task, ref: "t-1", title: "Escrever relatório")

  // MARK: - Period

  @Test func savesTheChosenPeriodAndAppliesTheAnswer() async {
    dashboard.apply(state(days: 7))
    let answer = state(days: 1)
    client.respond { _ in RecordingAPIClient.json(answer) }

    await store.chooseRange(1)

    #expect(client.calls.map(\.method) == ["PATCH"])
    #expect(client.calls.first?.path == "/api/preferences")
    #expect(client.calls.first?.body == #"{"agendaDays":1}"#)
    #expect(store.days == 1)
  }

  @Test func theActivePeriodIsNotSavedAgain() async {
    dashboard.apply(state(days: 2))
    await store.chooseRange(2)
    #expect(client.calls.isEmpty)
  }

  @Test func aRefusedPeriodKeepsTheOldOne() async {
    dashboard.apply(state(days: 2))
    client.respond { _ throws(APIError) in
      throw .server(status: 400, message: "período inválido", code: nil, retry: nil)
    }
    await store.chooseRange(7)
    #expect(store.days == 2)
  }

  // MARK: - Drop

  @Test func noCalendarMeansNoDropZone() {
    dashboard.apply(state())
    #expect(!store.acceptsDrops)
    #expect(!store.receiveDrop([source]))
    #expect(store.draft == nil)
  }

  @Test func aDropOpensTheSheetWithTheWebDefaults() {
    dashboard.apply(state(calendars: [readOnly, writable]))
    #expect(store.receiveDrop([source]))
    let draft = store.draft
    #expect(draft?.source == source)
    #expect(draft?.minutes == 50)
    #expect(draft?.start == localDate(2026, 9, 21, 10, 30))
    // The first writable calendar, not the first one listed.
    #expect(draft?.connectionId == "conn-google")
  }

  @Test func anInvalidDropIsIgnored() {
    dashboard.apply(state(calendars: [writable]))
    #expect(!store.receiveDrop([FocusSource(kind: .task, ref: "1", title: " ")]))
    #expect(store.draft == nil)
  }

  // MARK: - Scheduling

  @Test func createsTheBlockAndClosesTheSheet() async throws {
    dashboard.apply(state(calendars: [writable]))
    store.receiveDrop([source])
    let draft = try #require(store.draft)
    let created = AgendaItem(
      account: "conn-google", accountLabel: "Pessoal", date: "2026-09-21", time: "10:30", title: "Escrever relatório")
    client.respond { _ in RecordingAPIClient.json(FocusBlockResponse(item: created)) }

    await store.schedule(draft)

    #expect(client.calls.map(\.path) == ["/api/agenda/focus-blocks"])
    #expect(
      client.calls.first?.body
        == #"{"connectionId":"conn-google","item":{"kind":"task","ref":"t-1","title":"Escrever relatório"},"#
        + #""minutes":50,"start":"2026-09-21T13:30:00.000Z"}"#)
    #expect(store.draft == nil)
    #expect(store.items == [created])
  }

  @Test func a409ShowsTheReconnectText() async throws {
    dashboard.apply(state(calendars: [writable]))
    store.receiveDrop([source])
    let draft = try #require(store.draft)
    client.respond { _ throws(APIError) in throw .server(status: 409, message: "", code: nil, retry: nil) }

    await store.schedule(draft)

    #expect(store.reconnectMessage == FocusScheduler.reconnectMessage)
    #expect(store.draft != nil)
    #expect(
      store.reconnectURL(server: URL(string: "https://daily.example.com"), connectionId: draft.connectionId)?
        .absoluteString
        == "https://daily.example.com/api/integrations/agenda/google/start?login_hint=voce@example.com")
  }

  @Test func aServerErrorStaysInTheSheet() async throws {
    dashboard.apply(state(calendars: [writable]))
    store.receiveDrop([source])
    let draft = try #require(store.draft)
    client.respond { _ throws(APIError) in
      throw .server(status: 502, message: "Google indisponível", code: nil, retry: nil)
    }

    await store.schedule(draft)

    #expect(store.draftError == "Google indisponível")
    #expect(store.draft != nil)
  }

  @Test func aStartOutsideTheWindowIsRefusedBeforeTheCall() async throws {
    dashboard.apply(state(calendars: [writable]))
    store.receiveDrop([source])
    var draft = try #require(store.draft)
    draft.start = now.addingTimeInterval(-3600)

    await store.schedule(draft)

    #expect(store.draftError == "início inválido")
    #expect(client.calls.isEmpty)
  }
}
