import CoreGraphics
import DailyAPI
import DailyCore
import DailyModels
import Foundation
import Testing

@testable import FeatureHome

/// Sleeps until cancelled, so nothing scheduled ever fires on its own.
private let idle: Sleeper = { _ in
  try await Task.sleep(for: .seconds(3600))
}

/// Returns at once, so a debounced write happens on the next turn.
private let immediate: Sleeper = { _ in }

private struct SaveBody: Decodable, Equatable {
  struct Viewport: Decodable, Equatable {
    var width: Int
    var height: Int
  }

  var layout: [LayoutItem]
  var viewport: Viewport
}

private func item(_ module: ModuleID, x: Double, y: Double, w: Double, h: Double) -> LayoutItem {
  LayoutItem(i: module.rawValue, x: x, y: y, w: w, h: h)
}

@Suite struct GridGeometryTests {
  @Test func placementsBecomeFramesOnTwelveColumns() throws {
    // 1200 pt: columns of (1200 − 11 × 24) / 12 = 78 pt.
    let frames = GridDashboardLayout.frames(DashboardLayoutEngine.defaultLayout(), width: 1200)
    #expect(frames[.email] == CGRect(x: 0, y: 0, width: 690, height: 760))
    #expect(frames[.agenda] == CGRect(x: 714, y: 0, width: 486, height: 480))
    #expect(frames[.jira] == CGRect(x: 714, y: 504, width: 486, height: 648))
  }

  @Test func heightIsTheRowsTheLayoutUses() {
    let size = GridDashboardLayout.size(DashboardLayoutEngine.defaultLayout(), proposedWidth: 1200)
    // 36 rows: 36 × 32 + 35 × 24.
    #expect(size == CGSize(width: 1200, height: 1992))
    let unproposed = GridDashboardLayout.size([], proposedWidth: nil)
    #expect(unproposed == CGSize(width: GridDashboardLayout.fallbackWidth, height: 0))
  }

  @Test func arrangeMessageNamesTheWindowSize() {
    #expect(
      GridArrangeBar.message(for: CGSize(width: 1440.4, height: 899.6))
        == "Arraste para mover, puxe o canto para redimensionar. Salvar guarda para 1440 × 900.")
  }

  @Test func neighbouringPanelsJiggleOutOfStep() {
    #expect((0..<6).map(GridJiggle.duration(index:)) == [0.18, 0.22, 0.2, 0.22, 0.18, 0.2])
  }
}

@Suite struct NarrowDashboardTests {
  @Test func modulesFollowReadingOrder() {
    #expect(
      NarrowDashboard.modules(DashboardLayoutEngine.defaultLayout())
        == [.email, .agenda, .jira, .tasks, .pulls, .notes, .slack])
  }

  @Test func theChosenModuleWinsWhileShown() {
    let modules: [ModuleID] = [.email, .jira]
    #expect(NarrowDashboard.active(selected: nil, modules: modules) == .email)
    #expect(NarrowDashboard.active(selected: .jira, modules: modules) == .jira)
    #expect(NarrowDashboard.active(selected: .slack, modules: modules) == .email)
    #expect(NarrowDashboard.active(selected: nil, modules: []) == nil)
  }

  @Test func oneModuleNeedsNoBar() {
    #expect(!NarrowDashboard.showsBar(modules: [.email]))
    #expect(NarrowDashboard.showsBar(modules: [.email, .tasks]))
  }

  @Test func narrowUpToTheWebBreakpoint() {
    #expect(NarrowDashboard.isNarrow(width: 1023))
    #expect(!NarrowDashboard.isNarrow(width: 1024))
    #expect(!NarrowDashboard.isNarrow(width: 0))
  }
}

@Suite struct HomeGridStoreTests {
  let client = FakeAPIClient()
  let dashboard: DashboardStore
  let layoutStore: DashboardLayoutStore
  let store: HomeStore

  /// Email spans the whole width at 1440 × 900 and half of it at 1920 × 1080.
  static let wideEmail = SavedLayout(width: 1440, height: 900, layout: [item(.email, x: 0, y: 0, w: 12, h: 14)])
  static let halfEmail = SavedLayout(width: 1920, height: 1080, layout: [item(.email, x: 0, y: 0, w: 6, h: 14)])

  init() {
    let toasts = ToastCenter(sleep: idle)
    let storage = InMemorySessionStorage(server: URL(string: "https://daily.example.com"), token: "t")
    dashboard = DashboardStore(client: client, cache: nil, toasts: toasts)
    let session = SessionStore(client: client, tokenStore: storage, settings: storage)
    let pomodoro = PomodoroController(client: client, dashboard: dashboard, sleep: idle)
    layoutStore = DashboardLayoutStore(client: client, dashboard: dashboard, workspaceDirectory: nil)
    store = HomeStore(
      session: session, dashboard: dashboard, pomodoro: pomodoro, layoutStore: layoutStore, sleep: immediate)
  }

  func serve(layouts: [SavedLayout] = [], legacy: [LayoutItem] = []) {
    var state = Fixtures.full
    state.layouts = layouts
    state.layout = legacy
    dashboard.apply(state)
  }

  func email(_ layout: [PanelPlacement]) -> PanelPlacement? {
    layout.first { $0.i == .email }
  }

  @Test func theNearestSavedSizeWins() {
    serve(layouts: [Self.wideEmail, Self.halfEmail])
    store.updateWindowSize(CGSize(width: 1500, height: 950))
    #expect(email(store.fullLayout)?.w == 12)
    store.updateWindowSize(CGSize(width: 1900, height: 1000))
    #expect(email(store.fullLayout)?.w == 6)
  }

  @Test func withoutSizesTheLegacyLayoutThenTheDefault() {
    serve(legacy: [item(.email, x: 0, y: 0, w: 9, h: 14)])
    store.updateWindowSize(CGSize(width: 1500, height: 950))
    #expect(email(store.fullLayout)?.w == 9)
    serve()
    #expect(store.fullLayout == DashboardLayoutEngine.defaultLayout())
  }

  @Test func shownLayoutIsSanitizedAndOnlyEnabledModules() {
    var state = Fixtures.full
    state.modules = [.email, .slack]
    state.layout = [item(.email, x: 11, y: 3, w: 50, h: 1)]
    dashboard.apply(state)
    store.updateWindowSize(CGSize(width: 1500, height: 950))
    #expect(store.shownLayout.map(\.i) == [.email, .slack])
    // Clamped to 12 columns and 4 rows, then compacted to the top.
    #expect(email(store.shownLayout) == PanelPlacement(i: .email, x: 0, y: 0, w: 12, h: 4))
  }

  @Test func arrangingNeedsTheWideGrid() {
    serve()
    #expect(!store.canArrange)
    store.updateWindowSize(CGSize(width: 900, height: 700))
    #expect(store.isNarrow)
    store.beginArranging()
    #expect(!store.grid.isArranging)
    store.updateWindowSize(CGSize(width: 1500, height: 950))
    #expect(store.canArrange)
    store.beginArranging()
    #expect(store.grid.isArranging)
    #expect(!store.canArrange)
  }

  @Test func resizingTheWindowWhileArrangingKeepsTheLayout() {
    serve(layouts: [Self.wideEmail, Self.halfEmail])
    store.updateWindowSize(CGSize(width: 1500, height: 950))
    store.beginArranging()
    store.updateWindowSize(CGSize(width: 1900, height: 1000))
    #expect(email(store.gridLayout)?.w == 12)
    #expect(store.windowSize == CGSize(width: 1900, height: 1000))
    store.discardArrangement()
    #expect(email(store.gridLayout)?.w == 6)
  }

  @Test func goingNarrowEndsTheArrangeMode() {
    serve()
    store.updateWindowSize(CGSize(width: 1500, height: 950))
    store.beginArranging()
    store.movePanel(.agenda, x: 0, y: 0)
    store.updateWindowSize(CGSize(width: 900, height: 700))
    #expect(!store.grid.isArranging)
    #expect(store.grid.draft == nil)
  }

  @Test func movingAndResizingGoThroughTheEngine() {
    serve()
    store.updateWindowSize(CGSize(width: 1500, height: 950))
    let shown = store.shownLayout
    store.movePanel(.agenda, x: 0, y: 0)
    #expect(store.grid.draft == nil, "nothing moves outside the arrange mode")
    store.beginArranging()
    store.movePanel(.agenda, x: 0, y: 0)
    let moved = DashboardLayoutEngine.move(shown, id: .agenda, x: 0, y: 0)
    #expect(store.gridLayout == moved)
    store.resizePanel(.agenda, w: 12, h: 6)
    #expect(store.gridLayout == DashboardLayoutEngine.resize(moved, id: .agenda, w: 12, h: 6))
  }

  @Test func discardRestoresWithoutSaving() {
    serve()
    store.updateWindowSize(CGSize(width: 1500, height: 950))
    let shown = store.gridLayout
    store.beginArranging()
    store.movePanel(.slack, x: 0, y: 0)
    #expect(store.gridLayout != shown)
    store.discardArrangement()
    #expect(store.gridLayout == shown)
    #expect(!store.grid.isArranging)
    #expect(client.calls.isEmpty)
  }

  @Test func saveSendsTheDraftForTheWindowSize() async throws {
    serve()
    let answer = FakeAPIClient.json(LayoutResponse(layout: [], layouts: [Self.wideEmail]))
    client.respond { _ in answer }
    store.updateWindowSize(CGSize(width: 1500, height: 950))
    store.beginArranging()
    store.resizePanel(.email, w: 12, h: 14)
    await store.saveArrangement()

    let call = try #require(client.calls.first)
    #expect(client.calls.count == 1)
    #expect(call.method == "PATCH")
    #expect(call.path == "/api/preferences")
    let body = try JSONDecoder().decode(SaveBody.self, from: Data(try #require(call.body).utf8))
    #expect(body.viewport == SaveBody.Viewport(width: 1500, height: 950))
    #expect(body.layout.count == ModuleID.known.count)
    #expect(body.layout.first { $0.i == "email" }?.w == 12)
    #expect(!store.grid.isArranging)
    #expect(store.grid.draft == nil)
    #expect(layoutStore.layouts == [Self.wideEmail])
  }

  @Test func savingUntouchedPinsTheLayoutOnScreen() async throws {
    serve()
    let answer = FakeAPIClient.json(LayoutResponse(layout: [], layouts: []))
    client.respond { _ in answer }
    store.updateWindowSize(CGSize(width: 1500, height: 950))
    store.beginArranging()
    await store.saveArrangement()
    let call = try #require(client.calls.first)
    let body = try JSONDecoder().decode(SaveBody.self, from: Data(try #require(call.body).utf8))
    #expect(body.layout == DashboardLayoutEngine.serializeLayout(DashboardLayoutEngine.defaultLayout()))
  }

  @Test func aRefusedSaveShowsTheErrorAndLeavesTheMode() async {
    serve()
    let state = FakeAPIClient.json(Fixtures.full)
    client.respond { call throws(APIError) in
      if call.method == "PATCH" {
        throw .server(status: 400, message: "Disposição inválida", code: nil, retry: nil)
      }
      return state
    }
    store.updateWindowSize(CGSize(width: 1500, height: 950))
    store.beginArranging()
    await store.saveArrangement()
    #expect(store.layoutError == "Disposição inválida")
    #expect(!store.grid.isArranging)
  }

  @Test func narrowModulesFollowTheShownLayout() {
    serve()
    store.updateWindowSize(CGSize(width: 900, height: 700))
    #expect(store.narrowModules == [.email, .agenda, .jira, .tasks, .pulls, .notes, .slack])
    #expect(store.activeNarrowModule == .email)
    store.selectNarrowModule(.jira)
    #expect(store.activeNarrowModule == .jira)
  }

  @Test func theSwitchShowsOnlyWithModulesOn() {
    #expect(!store.showsViewSwitch)
    dashboard.apply(DashboardState(updatedAt: "2026-11-04T12:40:00.000Z", modules: []))
    #expect(!store.showsViewSwitch)
    serve()
    #expect(store.showsViewSwitch)
    #expect(!store.showsTabs)
  }

  @Test func choosingTabsEndsTheArrangeModeAndPatchesTheView() async {
    serve()
    store.updateWindowSize(CGSize(width: 1500, height: 950))
    store.beginArranging()
    let answer = FakeAPIClient.json(HomeViewResponse(homeView: .workspace))
    client.respond { _ in answer }
    await store.chooseView(.workspace)
    #expect(store.showsTabs)
    #expect(!store.grid.isArranging)
    let patch = FakeAPIClient.Call(method: "PATCH", path: "/api/preferences", body: #"{"homeView":"workspace"}"#)
    #expect(client.calls == [patch])
  }

  @Test func aRefusedViewGoesBackWithTheError() async {
    serve()
    client.respond { _ throws(APIError) in
      throw .server(status: 500, message: "", code: nil, retry: nil)
    }
    await store.chooseView(.workspace)
    #expect(!store.showsTabs)
    #expect(store.viewError == DashboardLayoutStore.homeViewFallback)
  }
}

@Suite struct HomeWorkspaceTests {
  let client = FakeAPIClient()
  let layoutStore: DashboardLayoutStore
  let account: LayoutAccount

  init() throws {
    let dashboard = DashboardStore(client: client, cache: nil, toasts: ToastCenter(sleep: idle))
    layoutStore = DashboardLayoutStore(client: client, dashboard: dashboard, workspaceDirectory: nil)
    let server = try #require(URL(string: "https://daily.example.com"))
    account = try #require(LayoutAccount(server: server, username: "ana"))
  }

  func saved() throws -> WorkspaceLayout? {
    guard let data = try layoutStore.loadWorkspace(account: account) else { return nil }
    return try WorkspaceLayout.decode(data)
  }

  @Test func nothingSavedStartsFromTheDefault() {
    let workspace = HomeWorkspace(store: layoutStore, sleep: immediate)
    workspace.load(account: account, modules: [.email, .tasks, .jira])
    #expect(workspace.layout == WorkspaceLayout.makeDefault(modules: [.email, .tasks, .jira]))
    #expect(workspace.isLoaded)
  }

  @Test func aSavedArrangementIsReadAndFollowsTheModules() throws {
    let base = WorkspaceLayout.makeDefault(modules: [.email, .tasks])
    let emailGroup = try #require(base.group(containing: .email))
    let joined = base.moving(.tasks, to: emailGroup.id)
    try layoutStore.saveWorkspace(joined.encoded(), account: account)

    let workspace = HomeWorkspace(store: layoutStore, sleep: immediate)
    workspace.load(account: account, modules: [.email, .tasks, .slack])
    #expect(workspace.layout == joined.reconciled(with: [.email, .tasks, .slack]))
    #expect(workspace.layout.views.contains(.slack))
  }

  @Test func anUnreadableFileFallsBackToTheDefault() throws {
    try layoutStore.saveWorkspace(Data("not json".utf8), account: account)
    let workspace = HomeWorkspace(store: layoutStore, sleep: immediate)
    workspace.load(account: account, modules: [.email, .tasks])
    #expect(workspace.layout == WorkspaceLayout.makeDefault(modules: [.email, .tasks]))
  }

  @Test func changesAreWrittenAfterTheDelay() async throws {
    let workspace = HomeWorkspace(store: layoutStore, sleep: immediate)
    workspace.load(account: account, modules: [.email, .tasks])
    let emailGroup = try #require(workspace.layout.group(containing: .email))
    let joined = workspace.layout.moving(.tasks, to: emailGroup.id)
    workspace.update(joined)
    await workspace.waitForPendingSave()
    #expect(try saved() == joined)
  }

  @Test func nothingIsWrittenBeforeTheDelay() throws {
    let workspace = HomeWorkspace(store: layoutStore, sleep: idle)
    workspace.load(account: account, modules: [.email, .tasks])
    let emailGroup = try #require(workspace.layout.group(containing: .email))
    workspace.update(workspace.layout.moving(.tasks, to: emailGroup.id))
    #expect(try saved() == nil)
  }

  @Test func aModuleTurnedOnGetsATabAndIsSaved() async throws {
    let workspace = HomeWorkspace(store: layoutStore, sleep: immediate)
    workspace.load(account: account, modules: [.email, .tasks])
    workspace.reconcile(modules: [.email, .tasks, .notes])
    #expect(workspace.layout.views.contains(.notes))
    await workspace.waitForPendingSave()
    #expect(try saved()?.views.contains(.notes) == true)
    workspace.reconcile(modules: [.email])
    #expect(workspace.layout.views == [.email])
  }

  @Test func restoreWritesTheDefaultAtOnce() throws {
    let workspace = HomeWorkspace(store: layoutStore, sleep: idle)
    workspace.load(account: account, modules: [.email, .tasks])
    let emailGroup = try #require(workspace.layout.group(containing: .email))
    workspace.update(workspace.layout.moving(.tasks, to: emailGroup.id))
    workspace.restore(modules: [.email, .tasks])
    let fallback = WorkspaceLayout.makeDefault(modules: [.email, .tasks])
    #expect(workspace.layout == fallback)
    #expect(try saved() == fallback)
  }

  @Test func withoutAnAccountTheArrangementStaysInMemory() async {
    let workspace = HomeWorkspace(store: layoutStore, sleep: immediate)
    workspace.load(account: nil, modules: [.email, .tasks])
    workspace.restore(modules: [.email])
    #expect(workspace.layout == WorkspaceLayout.makeDefault(modules: [.email]))
    #expect(workspace.saveError == nil)
  }
}
