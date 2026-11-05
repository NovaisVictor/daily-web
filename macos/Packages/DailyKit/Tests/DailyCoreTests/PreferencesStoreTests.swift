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

  /// A store signed in as `username` on `daily.example.com`.
  func makeStore(username: String = "ana") -> PreferencesStore {
    let store = PreferencesStore(client: client, dashboard: dashboard, toasts: toasts, defaults: defaults)
    store.activate(server: Self.server, username: username)
    return store
  }

  nonisolated static let server = URL(string: "https://daily.example.com") ?? URL(filePath: "/")

  nonisolated static func appearance(_ theme: AppearanceTheme? = nil, density: AppearanceDensity? = nil) -> Data {
    FakeAPIClient.json(AppearanceResponse(appearance: Appearance(theme: theme, density: density)))
  }

  /// The mirror keys are on disk: `AccountScope` keeps their format.
  @Test func mirrorKeysKeepTheirFormat() async {
    client.respond { _ in Self.appearance(.dark) }
    let store = makeStore()
    await store.updateAppearance(Appearance(theme: .dark))
    let key = "io.github.novaisvictor.dailyweb.appearance.https://daily.example.com|ana"
    #expect(defaults.string(forKey: "io.github.novaisvictor.dailyweb.appearanceAccount") == key)
    #expect(defaults.data(forKey: key) != nil)
    // A relaunch reads the mirror through the same key.
    let relaunched = PreferencesStore(client: client, dashboard: dashboard, toasts: toasts, defaults: defaults)
    #expect(relaunched.appearance.theme == .dark)
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

  @Test func overlappingFailureRollsBackOnlyItsOwnField() async {
    let store = makeStore()
    let themeGate = Gate()
    let densityGate = Gate()
    client.respond { call throws(APIError) in
      if call.body?.contains("theme") == true {
        await themeGate.wait()
        throw .offline
      }
      await densityGate.wait()
      return Self.appearance(density: .compact)
    }
    let theme = Task { await store.updateAppearance(Appearance(theme: .dark)) }
    await settle()
    let density = Task { await store.updateAppearance(Appearance(density: .compact)) }
    await settle()
    #expect(store.appearance == Appearance(theme: .dark, density: .compact))

    themeGate.open()
    _ = await theme.value
    // The theme save failed, so only the theme goes back; the density, still
    // being saved, stays.
    #expect(store.appearance == Appearance(density: .compact))

    densityGate.open()
    _ = await density.value
    #expect(store.appearance == Appearance(density: .compact))
    #expect(makeStore().appearance == Appearance(density: .compact))
  }

  @Test func staleSuccessDoesNotOverwriteALaterUpdate() async {
    let store = makeStore()
    let firstGate = Gate()
    client.respond { call throws(APIError) in
      if call.body?.contains("light") == true {
        await firstGate.wait()
        return Self.appearance(.light)
      }
      return Self.appearance(.dark)
    }
    let first = Task { await store.updateAppearance(Appearance(theme: .light)) }
    await settle()
    await store.updateAppearance(Appearance(theme: .dark))
    firstGate.open()
    _ = await first.value
    #expect(store.appearance == Appearance(theme: .dark))
  }

  @Test func staleFailureDoesNotUndoALaterUpdateOfTheSameField() async {
    let store = makeStore()
    let firstGate = Gate()
    client.respond { call throws(APIError) in
      if call.body?.contains("light") == true {
        await firstGate.wait()
        throw .offline
      }
      return Self.appearance(.dark)
    }
    let first = Task { await store.updateAppearance(Appearance(theme: .light)) }
    await settle()
    await store.updateAppearance(Appearance(theme: .dark))
    firstGate.open()
    _ = await first.value
    #expect(store.appearance == Appearance(theme: .dark))
  }

  @Test func mirrorIsKeptPerAccountAcrossSignOut() async {
    client.respond { _ in Self.appearance(.dark) }
    let store = makeStore(username: "ana")
    await store.updateAppearance(Appearance(theme: .dark))

    store.deactivate()
    #expect(store.appearance == Appearance())
    // Another person on the same Mac starts from the defaults.
    store.activate(server: Self.server, username: "bruno")
    #expect(store.appearance == Appearance())
    let otherServer = URL(string: "https://outro.example.com") ?? Self.server
    store.activate(server: otherServer, username: "ana")
    #expect(store.appearance == Appearance())
    // The same account finds its choice again.
    store.activate(server: Self.server, username: "ana")
    #expect(store.appearance == Appearance(theme: .dark))
  }

  @Test func launchUsesTheLastAccountsMirrorUntilSignOut() async {
    client.respond { _ in Self.appearance(.dark) }
    await makeStore().updateAppearance(Appearance(theme: .dark))
    let relaunched = PreferencesStore(client: client, dashboard: dashboard, toasts: toasts, defaults: defaults)
    #expect(relaunched.appearance == Appearance(theme: .dark))

    relaunched.deactivate()
    let afterSignOut = PreferencesStore(client: client, dashboard: dashboard, toasts: toasts, defaults: defaults)
    #expect(afterSignOut.appearance == Appearance())
  }

  @Test func answerForThePreviousAccountIsDiscarded() async {
    let store = makeStore(username: "ana")
    let gate = Gate()
    client.respond { _ in
      await gate.wait()
      return Self.appearance(.dark)
    }
    let pending = Task { await store.updateAppearance(Appearance(theme: .dark)) }
    await settle()
    store.deactivate()
    store.activate(server: Self.server, username: "bruno")
    gate.open()
    _ = await pending.value
    #expect(store.appearance == Appearance())
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

  @Test func agendaDaysFailureIsReturnedWithoutAToast() async {
    client.respond { _ throws(APIError) in throw .offline }
    let store = makeStore()
    let error = await store.setAgendaDays(7)
    #expect(error == .offline)
    #expect(toasts.toasts.isEmpty)
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
