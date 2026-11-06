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
  let window: HomeWindowState

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
    window = HomeWindowState(home: store)
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
    window.updateWindowSize(CGSize(width: 1500, height: 950))
    #expect(email(window.fullLayout)?.w == 12)
    window.updateWindowSize(CGSize(width: 1900, height: 1000))
    #expect(email(window.fullLayout)?.w == 6)
  }

  @Test func withoutSizesTheLegacyLayoutThenTheDefault() {
    serve(legacy: [item(.email, x: 0, y: 0, w: 9, h: 14)])
    window.updateWindowSize(CGSize(width: 1500, height: 950))
    #expect(email(window.fullLayout)?.w == 9)
    serve()
    #expect(window.fullLayout == DashboardLayoutEngine.defaultLayout())
  }

  @Test func shownLayoutIsSanitizedAndOnlyEnabledModules() {
    var state = Fixtures.full
    state.modules = [.email, .slack]
    state.layout = [item(.email, x: 11, y: 3, w: 50, h: 1)]
    dashboard.apply(state)
    window.updateWindowSize(CGSize(width: 1500, height: 950))
    #expect(window.shownLayout.map(\.i) == [.email, .slack])
    // Clamped to 12 columns and 4 rows, then compacted to the top.
    #expect(email(window.shownLayout) == PanelPlacement(i: .email, x: 0, y: 0, w: 12, h: 4))
  }

  @Test func arrangingNeedsTheWideGrid() {
    serve()
    #expect(!window.canArrange)
    window.updateWindowSize(CGSize(width: 900, height: 700))
    #expect(window.isNarrow)
    window.beginArranging()
    #expect(!window.grid.isArranging)
    window.updateWindowSize(CGSize(width: 1500, height: 950))
    #expect(window.canArrange)
    window.beginArranging()
    #expect(window.grid.isArranging)
    #expect(!window.canArrange)
  }

  @Test func resizingTheWindowWhileArrangingKeepsTheLayout() {
    serve(layouts: [Self.wideEmail, Self.halfEmail])
    window.updateWindowSize(CGSize(width: 1500, height: 950))
    window.beginArranging()
    window.updateWindowSize(CGSize(width: 1900, height: 1000))
    #expect(email(window.gridLayout)?.w == 12)
    #expect(window.windowSize == CGSize(width: 1900, height: 1000))
    window.discardArrangement()
    #expect(email(window.gridLayout)?.w == 6)
  }

  @Test func goingNarrowEndsTheArrangeMode() {
    serve()
    window.updateWindowSize(CGSize(width: 1500, height: 950))
    window.beginArranging()
    window.movePanel(.agenda, x: 0, y: 0)
    window.updateWindowSize(CGSize(width: 900, height: 700))
    #expect(!window.grid.isArranging)
    #expect(window.grid.draft == nil)
  }

  @Test func movingAndResizingGoThroughTheEngine() {
    serve()
    window.updateWindowSize(CGSize(width: 1500, height: 950))
    let shown = window.shownLayout
    window.movePanel(.agenda, x: 0, y: 0)
    #expect(window.grid.draft == nil, "nothing moves outside the arrange mode")
    window.beginArranging()
    window.movePanel(.agenda, x: 0, y: 0)
    let moved = DashboardLayoutEngine.move(shown, id: .agenda, x: 0, y: 0)
    #expect(window.gridLayout == moved)
    window.resizePanel(.agenda, w: 12, h: 6)
    #expect(window.gridLayout == DashboardLayoutEngine.resize(moved, id: .agenda, w: 12, h: 6))
  }

  @Test func discardRestoresWithoutSaving() {
    serve()
    window.updateWindowSize(CGSize(width: 1500, height: 950))
    let shown = window.gridLayout
    window.beginArranging()
    window.movePanel(.slack, x: 0, y: 0)
    #expect(window.gridLayout != shown)
    window.discardArrangement()
    #expect(window.gridLayout == shown)
    #expect(!window.grid.isArranging)
    #expect(client.calls.isEmpty)
  }

  @Test func saveSendsTheDraftForTheWindowSize() async throws {
    serve()
    let answer = FakeAPIClient.json(LayoutResponse(layout: [], layouts: [Self.wideEmail]))
    client.respond { _ in answer }
    window.updateWindowSize(CGSize(width: 1500, height: 950))
    window.beginArranging()
    window.resizePanel(.email, w: 12, h: 14)
    await window.saveArrangement()

    let call = try #require(client.calls.first)
    #expect(client.calls.count == 1)
    #expect(call.method == "PATCH")
    #expect(call.path == "/api/preferences")
    let body = try JSONDecoder().decode(SaveBody.self, from: Data(try #require(call.body).utf8))
    #expect(body.viewport == SaveBody.Viewport(width: 1500, height: 950))
    #expect(body.layout.count == ModuleID.known.count)
    #expect(body.layout.first { $0.i == "email" }?.w == 12)
    #expect(!window.grid.isArranging)
    #expect(window.grid.draft == nil)
    #expect(layoutStore.layouts == [Self.wideEmail])
  }

  @Test func savingUntouchedPinsTheLayoutOnScreen() async throws {
    serve()
    let answer = FakeAPIClient.json(LayoutResponse(layout: [], layouts: []))
    client.respond { _ in answer }
    window.updateWindowSize(CGSize(width: 1500, height: 950))
    window.beginArranging()
    await window.saveArrangement()
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
    window.updateWindowSize(CGSize(width: 1500, height: 950))
    window.beginArranging()
    await window.saveArrangement()
    #expect(store.layoutError == "Disposição inválida")
    #expect(!window.grid.isArranging)
  }

  @Test func narrowModulesFollowTheShownLayout() {
    serve()
    window.updateWindowSize(CGSize(width: 900, height: 700))
    #expect(window.narrowModules == [.email, .agenda, .jira, .tasks, .pulls, .notes, .slack])
    #expect(window.activeNarrowModule == .email)
    window.selectNarrowModule(.jira)
    #expect(window.activeNarrowModule == .jira)
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
    window.updateWindowSize(CGSize(width: 1500, height: 950))
    window.beginArranging()
    let answer = FakeAPIClient.json(HomeViewResponse(homeView: .workspace))
    client.respond { _ in answer }
    await window.chooseView(.workspace)
    #expect(store.showsTabs)
    #expect(!window.grid.isArranging)
    let patch = FakeAPIClient.Call(method: "PATCH", path: "/api/preferences", body: #"{"homeView":"workspace"}"#)
    #expect(client.calls == [patch])
  }

  @Test func aRefusedViewGoesBackWithTheError() async {
    serve()
    client.respond { _ throws(APIError) in
      throw .server(status: 500, message: "", code: nil, retry: nil)
    }
    await window.chooseView(.workspace)
    #expect(!store.showsTabs)
    #expect(store.viewError == DashboardLayoutStore.homeViewFallback)
  }

  /// Two main windows share the session's layouts but not their size, arrange
  /// mode or narrow module.
  @Test func eachWindowArrangesApart() {
    serve(layouts: [Self.wideEmail, Self.halfEmail])
    let other = HomeWindowState(home: store)
    window.updateWindowSize(CGSize(width: 1500, height: 950))
    other.updateWindowSize(CGSize(width: 1900, height: 1000))
    #expect(email(window.gridLayout)?.w == 12)
    #expect(email(other.gridLayout)?.w == 6)
    window.beginArranging()
    #expect(window.grid.isArranging)
    #expect(!other.grid.isArranging)
    #expect(other.canArrange)
    other.updateWindowSize(CGSize(width: 900, height: 700))
    other.selectNarrowModule(.jira)
    #expect(window.grid.isArranging, "the other window going narrow leaves this one arranging")
    #expect(other.activeNarrowModule == .jira)
  }

  /// A module that is off keeps its saved place when the others are saved.
  @Test func savingADraftKeepsThePlacesOfModulesThatAreOff() async throws {
    var state = Fixtures.full
    state.modules = [.email, .agenda]
    state.layout = [item(.slack, x: 6, y: 50, w: 6, h: 10)]
    state.layouts = []
    dashboard.apply(state)
    let answer = FakeAPIClient.json(LayoutResponse(layout: [], layouts: []))
    client.respond { _ in answer }
    window.updateWindowSize(CGSize(width: 1500, height: 950))
    window.beginArranging()
    window.resizePanel(.email, w: 12, h: 14)
    await window.saveArrangement()

    let call = try #require(client.calls.first)
    let body = try JSONDecoder().decode(SaveBody.self, from: Data(try #require(call.body).utf8))
    #expect(body.layout.first { $0.i == "slack" } == item(.slack, x: 6, y: 50, w: 6, h: 10))
    #expect(body.layout.first { $0.i == "email" }?.w == 12)
    #expect(body.layout.count == ModuleID.known.count)
  }

  // MARK: - "Organizar painéis" from the menu

  @Test func onlyTheKeyWindowAnswersTheMenu() {
    serve()
    let navigator = AppNavigator()
    window.updateWindowSize(CGSize(width: 1500, height: 950))
    navigator.requestArrange()
    window.handleArrangeRequest(from: navigator, isKeyWindow: false)
    #expect(!window.grid.isArranging)
    #expect(navigator.isArrangeRequested)
    window.handleArrangeRequest(from: navigator, isKeyWindow: true)
    #expect(window.grid.isArranging)
    #expect(!navigator.isArrangeRequested)
  }

  @Test func theRequestWaitsForTheStateAndTheWindowSize() {
    let navigator = AppNavigator()
    navigator.requestArrange()
    window.handleArrangeRequest(from: navigator, isKeyWindow: true)
    #expect(navigator.isArrangeRequested, "no state yet")
    serve()
    window.handleArrangeRequest(from: navigator, isKeyWindow: true)
    #expect(navigator.isArrangeRequested, "the window is not measured yet")
    window.updateWindowSize(CGSize(width: 1500, height: 950))
    window.handleArrangeRequest(from: navigator, isKeyWindow: true)
    #expect(window.grid.isArranging)
    #expect(!navigator.isArrangeRequested)
  }

  /// Where the grid cannot be arranged, the request is dropped rather than
  /// left to start arranging later.
  @Test func aNarrowWindowTakesTheRequestWithoutArranging() {
    serve()
    let navigator = AppNavigator()
    window.updateWindowSize(CGSize(width: 900, height: 700))
    navigator.requestArrange()
    window.handleArrangeRequest(from: navigator, isKeyWindow: true)
    #expect(!navigator.isArrangeRequested)
    #expect(!window.grid.isArranging)
    window.updateWindowSize(CGSize(width: 1500, height: 950))
    window.handleArrangeRequest(from: navigator, isKeyWindow: true)
    #expect(!window.grid.isArranging)
  }

  @Test func theTabsTakeTheRequestWithoutArranging() {
    var state = Fixtures.full
    state.homeView = .workspace
    dashboard.apply(state)
    let navigator = AppNavigator()
    navigator.requestArrange()
    window.handleArrangeRequest(from: navigator, isKeyWindow: true)
    #expect(!navigator.isArrangeRequested)
    #expect(!window.grid.isArranging)
  }

  // MARK: - Gestures

  /// A press on the agenda carried to the first column of a 936 pt grid.
  @discardableResult
  func dragAgenda(by dx: CGFloat = -560) -> Bool {
    window.dragPanel(
      .agenda, kind: .move, startLocation: CGPoint(x: 600, y: 20), translation: CGSize(width: dx, height: 0),
      containerWidth: 936)
  }

  @Test func aGestureShowsAPreviewAndWritesTheDraftOnRelease() {
    serve()
    window.updateWindowSize(CGSize(width: 1500, height: 950))
    let shown = window.gridLayout
    window.beginArranging()
    #expect(dragAgenda())
    let preview = DashboardLayoutEngine.dragPreview(startLayout: shown, id: .agenda, cell: GridCell(x: 0, y: 0))
    #expect(window.gridLayout == preview)
    #expect(window.grid.draft == nil, "nothing is written while the pointer is down")
    #expect(window.grid.activePanel == .agenda)
    #expect(window.grid.pointer.translation == CGSize(width: -560, height: 0))
    window.endPanelGesture()
    #expect(window.grid.draft == preview)
    #expect(window.grid.session == nil)
    #expect(window.grid.pointer.translation == .zero)
  }

  @Test func escCancelsTheGestureFirstThenLeavesTheMode() {
    serve()
    window.updateWindowSize(CGSize(width: 1500, height: 950))
    let shown = window.gridLayout
    window.beginArranging()
    dragAgenda()
    window.escapeArrangement()
    #expect(window.grid.isArranging, "the first Esc only cancels the gesture")
    #expect(window.grid.session == nil)
    #expect(window.gridLayout == shown, "the panel went back to where the gesture found it")
    #expect(window.grid.pointer.translation == .zero)
    #expect(!dragAgenda(by: -600), "the pointer is still down; its events do not restart the gesture")
    #expect(window.grid.session == nil)
    window.escapeArrangement()
    #expect(!window.grid.isArranging)
    #expect(client.calls.isEmpty)
  }

  @Test func escKeepsTheDraftOfEarlierGestures() {
    serve()
    window.updateWindowSize(CGSize(width: 1500, height: 950))
    window.beginArranging()
    window.movePanel(.slack, x: 0, y: 0)
    let draft = window.gridLayout
    dragAgenda()
    window.escapeArrangement()
    #expect(window.gridLayout == draft)
  }

  @Test func endingTheModeMidDragClearsTheGesture() {
    serve()
    window.updateWindowSize(CGSize(width: 1500, height: 950))
    let shown = window.gridLayout
    window.beginArranging()
    dragAgenda()
    // The drag surfaces go with the mode, so the drag's end is never heard.
    window.updateWindowSize(CGSize(width: 900, height: 700))
    #expect(!window.grid.isArranging)
    #expect(window.grid.session == nil)
    #expect(window.grid.activePanel == nil)
    #expect(window.grid.pointer.translation == .zero)
    window.updateWindowSize(CGSize(width: 1500, height: 950))
    window.beginArranging()
    #expect(window.grid.session == nil)
    #expect(window.gridLayout == shown)

    dragAgenda()
    window.discardArrangement()
    #expect(window.grid.session == nil)
    #expect(window.gridLayout == shown)
  }

  @Test func aPanelThatIsOffIsNotDragged() {
    var state = Fixtures.full
    state.modules = [.email, .agenda]
    dashboard.apply(state)
    window.updateWindowSize(CGSize(width: 1500, height: 950))
    window.beginArranging()
    let changed = window.dragPanel(
      .slack, kind: .move, startLocation: .zero, translation: CGSize(width: 200, height: 200), containerWidth: 936)
    #expect(!changed)
    #expect(window.grid.session == nil)
  }

  @Test func savingMidGestureSavesWhatIsOnScreen() async throws {
    serve()
    let answer = FakeAPIClient.json(LayoutResponse(layout: [], layouts: []))
    client.respond { _ in answer }
    window.updateWindowSize(CGSize(width: 1500, height: 950))
    window.beginArranging()
    dragAgenda()
    await window.saveArrangement()
    let call = try #require(client.calls.first)
    let body = try JSONDecoder().decode(SaveBody.self, from: Data(try #require(call.body).utf8))
    #expect(body.layout.first { $0.i == "agenda" }?.x == 0)
    #expect(window.grid.session == nil)
  }

  @Test func arrowsMoveAndShiftArrowsResizeTheFocusedPanel() {
    serve()
    window.updateWindowSize(CGSize(width: 1500, height: 950))
    window.nudgePanel(.agenda, dx: -1, dy: 0, resizing: false)
    #expect(window.grid.draft == nil, "nothing moves outside the arrange mode")
    window.beginArranging()
    window.nudgePanel(.agenda, dx: -1, dy: 0, resizing: false)
    #expect(window.gridLayout.first { $0.i == .agenda }?.x == 6)
    window.nudgePanel(.agenda, dx: 1, dy: 1, resizing: true)
    let agenda = window.gridLayout.first { $0.i == .agenda }
    #expect(agenda?.w == 6)
    #expect(agenda?.h == 10)
  }

  // MARK: - A save still waiting for the server

  /// A server that answers the save only when `release` is called.
  func holdTheSave() -> AsyncStream<Void>.Continuation {
    let (gate, release) = AsyncStream.makeStream(of: Void.self)
    let answer = FakeAPIClient.json(LayoutResponse(layout: [], layouts: []))
    client.respond { _ in
      var waiting = gate.makeAsyncIterator()
      _ = await waiting.next()
      return answer
    }
    return release
  }

  func waitForTheSaveToBeSent() async throws {
    for _ in 0..<1000 where client.calls.isEmpty {
      await Task.yield()
    }
    try #require(!client.calls.isEmpty)
  }

  @Test func discardingWhileASaveIsPendingKeepsTheModeOff() async throws {
    serve()
    let release = holdTheSave()
    window.updateWindowSize(CGSize(width: 1500, height: 950))
    window.beginArranging()
    let window = window
    let saving = Task { await window.saveArrangement() }
    try await waitForTheSaveToBeSent()
    #expect(window.grid.isSaving)
    window.discardArrangement()
    #expect(!window.grid.isArranging)
    release.yield()
    release.finish()
    await saving.value
    #expect(!window.grid.isArranging)
    #expect(!window.grid.isSaving)
  }

  @Test func aLateSaveDoesNotEndANewerMode() async throws {
    serve()
    let release = holdTheSave()
    window.updateWindowSize(CGSize(width: 1500, height: 950))
    window.beginArranging()
    let window = window
    let saving = Task { await window.saveArrangement() }
    try await waitForTheSaveToBeSent()
    window.discardArrangement()
    window.beginArranging()
    window.movePanel(.slack, x: 0, y: 0)
    release.yield()
    release.finish()
    await saving.value
    #expect(window.grid.isArranging)
    #expect(window.grid.draft != nil)
  }

  // MARK: - "Concluir organização" from the menu

  @Test func theMenuItemTogglesWithTheMode() async throws {
    serve()
    let answer = FakeAPIClient.json(LayoutResponse(layout: [], layouts: []))
    client.respond { _ in answer }
    window.updateWindowSize(CGSize(width: 1500, height: 950))
    #expect(ArrangeMenuCommand(window.arrangeMenu) == .organize)
    window.beginArranging()
    #expect(ArrangeMenuCommand(window.arrangeMenu) == .finish)
    await window.finishArranging()
    let call = try #require(client.calls.first)
    #expect(call.method == "PATCH")
    #expect(call.path == "/api/preferences")
    #expect(!window.grid.isArranging)
    #expect(ArrangeMenuCommand(window.arrangeMenu) == .organize)
    await window.finishArranging()
    #expect(client.calls.count == 1, "finishing outside the mode saves nothing")
  }
}

@Suite struct GridArrangementMergeTests {
  @Test func theDraftIsLaidOverTheFullLayout() {
    let full = [
      PanelPlacement(i: .email, x: 0, y: 0, w: 6, h: 10),
      PanelPlacement(i: .slack, x: 6, y: 40, w: 6, h: 8),
      PanelPlacement(i: .tasks, x: 0, y: 10, w: 6, h: 8),
    ]
    let draft = [
      PanelPlacement(i: .tasks, x: 6, y: 0, w: 6, h: 8),
      PanelPlacement(i: .email, x: 0, y: 0, w: 6, h: 12),
    ]
    let merged = GridArrangement.merge(draft, over: full)
    #expect(merged.map(\.i) == [.email, .slack, .tasks])
    #expect(merged[0] == draft[1])
    #expect(merged[1] == full[1])
    #expect(merged[2] == draft[0])
  }

  @Test func aDraftPanelMissingFromTheFullLayoutIsKept() {
    let full = [PanelPlacement(i: .email, x: 0, y: 0, w: 6, h: 10)]
    let draft = [PanelPlacement(i: .notes, x: 6, y: 0, w: 6, h: 8)]
    #expect(GridArrangement.merge(draft, over: full) == full + draft)
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

  /// `page.tsx:97-100`: the saved file goes and the default shows; a change
  /// still waiting is dropped instead of writing over the removal.
  @Test func restoreRemovesTheSavedArrangement() async throws {
    let base = WorkspaceLayout.makeDefault(modules: [.email, .tasks])
    let emailGroup = try #require(base.group(containing: .email))
    try layoutStore.saveWorkspace(base.moving(.tasks, to: emailGroup.id).encoded(), account: account)
    let workspace = HomeWorkspace(store: layoutStore, sleep: immediate)
    workspace.load(account: account, modules: [.email, .tasks])
    let tasksGroup = try #require(base.group(containing: .tasks))
    workspace.update(base.moving(.email, to: tasksGroup.id))
    workspace.restore(account: account, modules: [.email, .tasks])
    await workspace.waitForPendingSave()
    #expect(workspace.layout == base)
    #expect(try saved() == nil)
    #expect(workspace.saveError == nil)
  }

  /// Restoring before the tabs were read loads the account first, so the
  /// removal reaches its file and later changes are written there.
  @Test func restoreBeforeLoadingLoadsTheAccountFirst() async throws {
    let base = WorkspaceLayout.makeDefault(modules: [.email, .tasks])
    let emailGroup = try #require(base.group(containing: .email))
    try layoutStore.saveWorkspace(base.moving(.tasks, to: emailGroup.id).encoded(), account: account)
    let workspace = HomeWorkspace(store: layoutStore, sleep: immediate)
    workspace.restore(account: account, modules: [.email, .tasks])
    #expect(workspace.isLoaded)
    #expect(workspace.layout == base)
    #expect(try saved() == nil)
    workspace.reconcile(modules: [.email, .tasks, .notes])
    await workspace.waitForPendingSave()
    #expect(try saved()?.views.contains(.notes) == true)
  }

  @Test func withoutAnAccountTheArrangementStaysInMemory() async {
    let workspace = HomeWorkspace(store: layoutStore, sleep: immediate)
    workspace.load(account: nil, modules: [.email, .tasks])
    workspace.restore(account: nil, modules: [.email])
    #expect(workspace.layout == WorkspaceLayout.makeDefault(modules: [.email]))
    #expect(workspace.saveError == nil)
  }
}
