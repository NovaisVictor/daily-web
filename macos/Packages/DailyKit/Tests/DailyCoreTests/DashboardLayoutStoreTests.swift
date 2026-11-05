import DailyAPI
import DailyModels
import Foundation
import Testing

@testable import DailyCore

@Suite struct DashboardLayoutStoreTests {
  let client = FakeAPIClient()
  let toasts: ToastCenter
  let dashboard: DashboardStore

  init() {
    toasts = quietToasts()
    dashboard = DashboardStore(client: client, cache: nil, toasts: toasts)
    dashboard.apply(Fixtures.state())
  }

  func makeStore(directory: URL? = nil) -> DashboardLayoutStore {
    DashboardLayoutStore(client: client, dashboard: dashboard, workspaceDirectory: directory)
  }

  nonisolated static let email = LayoutItem(i: "email", x: 0, y: 0, w: 7, h: 14)
  nonisolated static let movedEmail = LayoutItem(i: "email", x: 5, y: 0, w: 7, h: 14)
  nonisolated static let server = URL(string: "https://daily.example.com") ?? URL(filePath: "/")

  func account(_ username: String = "ana", server: URL = Self.server) throws -> LayoutAccount {
    try #require(LayoutAccount(server: server, username: username))
  }

  // MARK: - Reading

  @Test func readsTheArrangementFromTheDashboardState() {
    var state = Fixtures.state()
    state.layout = [Self.email]
    state.layouts = [SavedLayout(width: 1440, height: 900, layout: [Self.movedEmail])]
    state.homeView = .workspace
    dashboard.apply(state)
    let store = makeStore()
    #expect(store.layout == [Self.email])
    #expect(store.layouts == state.layouts)
    #expect(store.homeView == .workspace)
  }

  @Test func withoutAStateTheHomeIsTheGrid() {
    dashboard.clear()
    let store = makeStore()
    #expect(store.homeView == .grid)
    #expect(store.layout.isEmpty && store.layouts.isEmpty)
  }

  // MARK: - Saving the grid

  @Test func saveSendsTheLayoutAndViewportAndAppliesTheAnswer() async {
    let saved = [SavedLayout(width: 1440, height: 900, layout: [Self.movedEmail])]
    client.respond { _ in FakeAPIClient.json(LayoutResponse(layout: [Self.email], layouts: saved)) }
    let store = makeStore()
    let error = await store.saveGrid([Self.movedEmail], viewport: CGSize(width: 1439.6, height: 900.2))
    #expect(error == nil)
    #expect(
      client.calls == [
        .init(
          method: "PATCH", path: "/api/preferences",
          body: #"{"layout":[{"h":14,"i":"email","w":7,"x":5,"y":0}],"viewport":{"height":900,"width":1440}}"#)
      ])
    #expect(dashboard.state?.layouts == saved)
    #expect(dashboard.state?.layout == [Self.email])
    #expect(store.layoutError == nil)
    #expect(!store.isSavingGrid)
  }

  @Test func saveFailureShowsTheServerTextAndReloads() async {
    var fresh = Fixtures.state(updatedAt: "reloaded")
    fresh.layout = [Self.email]
    client.respond { [fresh] call throws(APIError) in
      if call.path == "/api/state" { return FakeAPIClient.json(fresh) }
      throw .server(status: 400, message: "tamanho de tela inválido", code: nil, retry: nil)
    }
    let store = makeStore()
    let error = await store.saveGrid([Self.movedEmail], viewport: CGSize(width: 0, height: 0))
    #expect(error == .server(status: 400, message: "tamanho de tela inválido", code: nil, retry: nil))
    #expect(store.layoutError == "tamanho de tela inválido")
    #expect(client.calls.map(\.path) == ["/api/preferences", "/api/state"])
    #expect(dashboard.state == fresh)
    // Shown inline on the home screen, as the web does, not as a toast.
    #expect(toasts.toasts.isEmpty)
  }

  @Test func saveFailureWithoutAMessageUsesTheWebFallback() async {
    client.respond { call throws(APIError) in
      if call.path == "/api/state" { return FakeAPIClient.json(Fixtures.state()) }
      throw .invalidResponse
    }
    let store = makeStore()
    await store.saveGrid([Self.email], viewport: CGSize(width: 1440, height: 900))
    #expect(store.layoutError == "Falha ao guardar a disposição dos painéis")
  }

  @Test func aGoodSaveClearsThePreviousError() async {
    client.respond { call throws(APIError) in
      if call.path == "/api/state" { return FakeAPIClient.json(Fixtures.state()) }
      throw .offline
    }
    let store = makeStore()
    await store.saveGrid([Self.email], viewport: CGSize(width: 1440, height: 900))
    #expect(store.layoutError == "Sem conexão com o servidor.")
    client.respond { _ in FakeAPIClient.json(LayoutResponse(layout: [Self.email], layouts: [])) }
    await store.saveGrid([Self.email], viewport: CGSize(width: 1440, height: 900))
    #expect(store.layoutError == nil)
  }

  // MARK: - Default and reset

  @Test func resetSendsANullLayoutAndAppliesTheAnswer() async {
    var state = Fixtures.state()
    state.layout = [Self.movedEmail]
    state.layouts = [SavedLayout(width: 1440, height: 900, layout: [Self.movedEmail])]
    dashboard.apply(state)
    client.respond { _ in FakeAPIClient.json(LayoutResponse(layout: [Self.email], layouts: [])) }
    let store = makeStore()
    let error = await store.resetGrid()
    #expect(error == nil)
    #expect(client.calls == [.init(method: "PATCH", path: "/api/preferences", body: #"{"layout":null}"#)])
    #expect(dashboard.state?.layout == [Self.email])
    #expect(dashboard.state?.layouts == [])
    #expect(store.isDefaultGrid == true)
    #expect(!store.isResettingGrid)
  }

  @Test func resetFailureUsesTheWebText() async {
    client.respond { _ throws(APIError) in throw .server(status: 500, message: "erro", code: nil, retry: nil) }
    let store = makeStore()
    let error = await store.resetGrid()
    #expect(error != nil)
    #expect(store.resetError == "Falha ao restaurar a disposição")
    #expect(store.isDefaultGrid == nil)
  }

  @Test func checkComparesWithTheServersDefault() async {
    var state = Fixtures.state()
    state.layout = [Self.email]
    dashboard.apply(state)
    client.respond { _ in FakeAPIClient.json(LayoutDefaultResponse(layout: [Self.email])) }
    let store = makeStore()
    await store.checkDefaultGrid()
    #expect(client.calls == [.init(method: "GET", path: "/api/preferences/layout-default", body: nil)])
    #expect(store.isDefaultGrid == true)

    state.layout = [Self.movedEmail]
    dashboard.apply(state)
    await store.checkDefaultGrid()
    #expect(store.isDefaultGrid == false)
  }

  @Test func aLayoutSavedForSomeSizeIsNotTheDefault() async {
    var state = Fixtures.state()
    state.layout = [Self.email]
    state.layouts = [SavedLayout(width: 1440, height: 900, layout: [Self.movedEmail])]
    dashboard.apply(state)
    client.respond { _ in FakeAPIClient.json(LayoutDefaultResponse(layout: [Self.email])) }
    let store = makeStore()
    await store.checkDefaultGrid()
    #expect(store.isDefaultGrid == false)
  }

  @Test func checkFailureLeavesTheAnswerUnknownAndShowsTheError() async {
    client.respond { _ throws(APIError) in throw .offline }
    let store = makeStore()
    #expect(await store.checkDefaultGrid() == .offline)
    #expect(store.isDefaultGrid == nil)
    #expect(store.checkError == "Sem conexão com o servidor.")
    client.respond { _ in FakeAPIClient.json(LayoutDefaultResponse(layout: [Self.email])) }
    await store.checkDefaultGrid()
    #expect(store.checkError == nil)
  }

  @Test func aCancelledCheckIsNoFailure() async {
    client.respond { _ throws(APIError) in throw .cancelled }
    let store = makeStore()
    #expect(await store.checkDefaultGrid() == .cancelled)
    #expect(store.checkError == nil)
  }

  /// The web compares the JSON strings (`LayoutPanel.tsx:30`), so the order counts too.
  @Test func anotherOrderIsNotTheDefault() async {
    let tasks = LayoutItem(i: "tasks", x: 7, y: 0, w: 5, h: 12)
    var state = Fixtures.state()
    state.layout = [tasks, Self.email]
    dashboard.apply(state)
    client.respond { _ in FakeAPIClient.json(LayoutDefaultResponse(layout: [Self.email, tasks])) }
    let store = makeStore()
    await store.checkDefaultGrid()
    #expect(store.isDefaultGrid == false)
  }

  /// Configuração → Disposição stays open while a window saves its grid: the
  /// restore must show without asking the server again.
  @Test func aSaveForSomeSizeAfterTheCheckIsNoLongerTheDefault() async {
    var state = Fixtures.state()
    state.layout = [Self.email]
    state.layouts = []
    dashboard.apply(state)
    client.respond { _ in FakeAPIClient.json(LayoutDefaultResponse(layout: [Self.email])) }
    let store = makeStore()
    await store.checkDefaultGrid()
    #expect(store.isDefaultGrid == true)
    let saved = [SavedLayout(width: 1440, height: 900, layout: [Self.movedEmail])]
    client.respond { _ in FakeAPIClient.json(LayoutResponse(layout: [Self.email], layouts: saved)) }
    await store.saveGrid([Self.movedEmail], viewport: CGSize(width: 1440, height: 900))
    #expect(store.isDefaultGrid == false)
    #expect(client.calls.count == 2)
  }

  @Test func withoutTheDashboardTheAnswerIsUnknown() async {
    client.respond { _ in FakeAPIClient.json(LayoutDefaultResponse(layout: [Self.email])) }
    let store = makeStore()
    await store.checkDefaultGrid()
    dashboard.clear()
    #expect(store.isDefaultGrid == nil)
  }

  // MARK: - Grade / Abas

  @Test func homeViewChangesAtOnceAndIsSaved() async {
    let gate = Gate()
    client.respond { _ in
      await gate.wait()
      return FakeAPIClient.json(HomeViewResponse(homeView: .workspace))
    }
    let store = makeStore()
    let pending = Task { await store.setHomeView(.workspace) }
    await settle()
    #expect(store.homeView == .workspace)
    gate.open()
    #expect(await pending.value == nil)
    #expect(client.calls == [.init(method: "PATCH", path: "/api/preferences", body: #"{"homeView":"workspace"}"#)])
    #expect(store.homeView == .workspace)
    #expect(store.viewError == nil)
  }

  @Test func homeViewFailureGoesBackWithTheWebText() async {
    client.respond { _ throws(APIError) in throw .invalidResponse }
    let store = makeStore()
    let error = await store.setHomeView(.workspace)
    #expect(error == .invalidResponse)
    #expect(store.homeView == .grid)
    #expect(store.viewError == "Falha ao guardar a disposição do Início")
    #expect(toasts.toasts.isEmpty)
  }

  @Test func homeViewFailureShowsTheServerText() async {
    client.respond { _ throws(APIError) in
      throw .server(status: 400, message: "visualização do início inválida", code: nil, retry: nil)
    }
    let store = makeStore()
    await store.setHomeView(.workspace)
    #expect(store.viewError == "visualização do início inválida")
  }

  @Test func choosingTheCurrentViewSendsNothing() async {
    let store = makeStore()
    #expect(await store.setHomeView(.grid) == nil)
    #expect(client.calls.isEmpty)
  }

  @Test func aStaleFailureDoesNotUndoALaterSwitch() async {
    let firstGate = Gate()
    client.respond { call throws(APIError) in
      if call.body?.contains("workspace") == true {
        await firstGate.wait()
        throw .offline
      }
      return FakeAPIClient.json(HomeViewResponse(homeView: .grid))
    }
    let store = makeStore()
    let first = Task { await store.setHomeView(.workspace) }
    await settle()
    await store.setHomeView(.grid)
    #expect(store.homeView == .grid)
    firstGate.open()
    _ = await first.value
    #expect(store.homeView == .grid)
  }

  // MARK: - Abas on disk

  @Test func workspaceIsKeptPerAccountOnDisk() throws {
    let directory = Fixtures.temporaryDirectory()
    let store = makeStore(directory: directory)
    let ana = try account("ana")
    #expect(try store.loadWorkspace(account: ana) == nil)

    let data = Data(#"{"schema":1}"#.utf8)
    try store.saveWorkspace(data, account: ana)
    // A relaunch finds it.
    #expect(try makeStore(directory: directory).loadWorkspace(account: ana) == data)
    // Another person, or the same name on another server, starts empty.
    #expect(try store.loadWorkspace(account: account("bruno")) == nil)
    let other = URL(string: "https://outro.example.com") ?? Self.server
    #expect(try store.loadWorkspace(account: account("ana", server: other)) == nil)

    try store.removeWorkspace(account: ana)
    #expect(try store.loadWorkspace(account: ana) == nil)
    try store.removeWorkspace(account: ana)
  }

  @Test func theFileNameNeverCarriesTheUsername() throws {
    let name = try account("ana.silva").fileName
    #expect(!name.contains("ana"))
    #expect(name.hasPrefix("home-workspace-") && name.hasSuffix(".json"))
    // The same origin written differently is the same account.
    let sameOrigin = URL(string: "HTTPS://Daily.Example.com:443/") ?? Self.server
    #expect(try account("ana.silva", server: sameOrigin).fileName == name)
  }

  @Test func aCorruptFileThrows() throws {
    let directory = Fixtures.temporaryDirectory()
    let ana = try account()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("not json".utf8).write(to: directory.appending(path: ana.fileName))
    #expect(throws: (any Error).self) { try makeStore(directory: directory).loadWorkspace(account: ana) }
  }

  @Test func withoutADirectoryTheWorkspaceStaysInMemory() throws {
    let store = makeStore()
    let ana = try account()
    try store.saveWorkspace(Data("x".utf8), account: ana)
    #expect(try store.loadWorkspace(account: ana) == Data("x".utf8))
    try store.removeWorkspace(account: ana)
    #expect(try store.loadWorkspace(account: ana) == nil)
  }

  @Test func aServerWithoutAnHTTPOriginHasNoAccount() {
    #expect(LayoutAccount(server: URL(filePath: "/tmp"), username: "ana") == nil)
  }
}
