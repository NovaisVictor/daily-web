import DailyAPI
import DailyModels
import Foundation
import Testing

@testable import DailyCore

@Suite struct PreferencesStoreTests {
  let client = FakeAPIClient()
  let toasts: ToastCenter
  let defaults = Fixtures.defaults()
  let dashboard: DashboardStore

  init() {
    toasts = quietToasts()
    dashboard = DashboardStore(client: client, cache: nil, toasts: toasts)
    dashboard.apply(Fixtures.state())
  }

  func makeStore() -> PreferencesStore {
    PreferencesStore(client: client, dashboard: dashboard, toasts: toasts, defaults: defaults)
  }

  @Test func appearanceSendsOnlyTheChangedFieldAndMirrorsTheAnswer() async {
    client.respond { _ in
      FakeAPIClient.json(AppearanceResponse(appearance: Appearance(theme: .dark, density: .compact)))
    }
    let store = makeStore()
    let error = await store.updateAppearance(Appearance(theme: .dark))
    #expect(error == nil)
    #expect(
      client.calls == [.init(method: "PATCH", path: "/api/preferences", body: #"{"appearance":{"theme":"dark"}}"#)])
    #expect(store.appearance == Appearance(theme: .dark, density: .compact))
    // A new launch reads the mirror before any network answer.
    #expect(makeStore().appearance == Appearance(theme: .dark, density: .compact))
  }

  @Test func appearanceFailureGoesBack() async {
    let store = makeStore()
    client.respond { _ throws(APIError) in
      throw .server(status: 400, message: "aparência inválida", code: nil, retry: nil)
    }
    await store.updateAppearance(Appearance(width: .limited))
    #expect(store.appearance == Appearance())
    #expect(makeStore().appearance == Appearance())
    #expect(toasts.toasts.map(\.text) == ["aparência inválida"])
  }

  @Test func agendaDaysAppliesTheWholeState() async {
    var fresh = Fixtures.state(updatedAt: "refetched")
    fresh.agendaDays = 7
    client.respond { [fresh] _ in FakeAPIClient.json(fresh) }
    let store = makeStore()
    await store.setAgendaDays(7)
    #expect(client.calls == [.init(method: "PATCH", path: "/api/preferences", body: #"{"agendaDays":7}"#)])
    #expect(dashboard.state == fresh)
  }

  @Test func agendaDaysOutsideTheServerRangeIsRefused() async {
    let store = makeStore()
    let error = await store.setAgendaDays(5)
    #expect(error == .server(status: 400, message: "período inválido", code: nil, retry: nil))
    #expect(client.calls.isEmpty)
  }

  @Test func tasksViewIsOptimistic() async {
    let store = makeStore()
    client.respond { _ in FakeAPIClient.json(TasksViewResponse(tasksView: .board)) }
    await store.setTasksView(.board)
    #expect(client.calls == [.init(method: "PATCH", path: "/api/preferences", body: #"{"tasksView":"board"}"#)])
    #expect(dashboard.state?.tasksView == .board)

    client.respond { _ throws(APIError) in throw .offline }
    await store.setTasksView(.list)
    #expect(dashboard.state?.tasksView == .board)
    #expect(toasts.toasts.map(\.text) == ["Sem conexão com o servidor."])
  }
}
