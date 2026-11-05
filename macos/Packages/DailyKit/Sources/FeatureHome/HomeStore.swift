import DailyAPI
import DailyCore
import DailyModels
import Foundation
import Observation

/// What Início reads: the greeting, the pomodoro, the module panels and how
/// they are arranged (grid or tabs, spec 010). It has no endpoint of its own;
/// the pomodoro goes through the shared `PomodoroController` and the
/// arrangement through `DashboardLayoutStore`.
///
/// One per session, so the app menu's "Organizar painéis" reaches the same
/// store the screen shows.
@Observable
public final class HomeStore {
  static let storeKey = "home"
  /// Shared with whatever else needs the arrangement (Configuração → Disposição).
  static let layoutStoreKey = "dashboardLayout"

  @ObservationIgnored private let session: SessionStore
  @ObservationIgnored private let dashboard: DashboardStore
  @ObservationIgnored private let pomodoro: PomodoroController
  @ObservationIgnored private let poller: Poller?
  @ObservationIgnored let layoutStore: DashboardLayoutStore
  let grid: GridArrangement
  let workspace: HomeWorkspace

  /// The window's content size, as the web's `window.innerWidth/innerHeight`.
  private(set) var windowSize: CGSize = .zero
  /// The size the grid layout is chosen for. It stays put while arranging, so
  /// resizing the window then does not swap the layout under the draft.
  private var layoutSize: CGSize = .zero
  /// The module the narrow grid shows, as the web's `?modulo=`.
  private var narrowSelection: ModuleID?

  init(
    session: SessionStore, dashboard: DashboardStore, pomodoro: PomodoroController,
    layoutStore: DashboardLayoutStore, poller: Poller? = nil, sleep: @escaping Sleeper = LiveTime.sleep
  ) {
    self.session = session
    self.dashboard = dashboard
    self.pomodoro = pomodoro
    self.poller = poller
    self.layoutStore = layoutStore
    grid = GridArrangement(layoutStore: layoutStore)
    workspace = HomeWorkspace(store: layoutStore, sleep: sleep)
  }

  convenience init(environment: AppEnvironment, workspaceDirectory: URL?) {
    let layoutStore = environment.featureStores.store(HomeStore.layoutStoreKey) {
      DashboardLayoutStore(
        client: environment.client, dashboard: environment.dashboard, workspaceDirectory: workspaceDirectory)
    }
    self.init(
      session: environment.session, dashboard: environment.dashboard, pomodoro: environment.pomodoro,
      layoutStore: layoutStore, poller: environment.poller)
  }

  /// The session's store, created on first use.
  ///
  /// - Parameter workspaceDirectory: Where the "Abas" arrangement is kept; nil
  ///   keeps it in memory (previews). Only the first call's value counts.
  public static func shared(
    in environment: AppEnvironment, workspaceDirectory: URL? = AppEnvironment.defaultCacheDirectory
  ) -> HomeStore {
    environment.featureStores.store(storeKey) {
      HomeStore(environment: environment, workspaceDirectory: workspaceDirectory)
    }
  }

  // MARK: - Now band

  /// Whether some window of the app is on screen (the app delegate feeds the
  /// poller from the occlusion state). The clock stops ticking otherwise: a
  /// per-second redraw of a hidden window cost ~2.7% CPU (NFR-001).
  var isOnScreen: Bool { poller?.isForeground ?? true }

  /// `GET /api/me` does not say how many times the person signed in, so the app
  /// cannot tell a first visit (`welcomeKind` in `lib/preferences.ts:220-223`).
  /// Whoever opens the native app has an account already, so it welcomes them back.
  var greeting: Greeting {
    Greeting(user: session.user, welcome: .returning)
  }

  /// Nil when the server has no timer yet or it is switched off; the web then
  /// renders nothing (`components/Pomodoro.tsx:80`).
  var timer: PomodoroDisplay? {
    guard let display = pomodoro.display, display.enabled else { return nil }
    return display
  }

  var timerError: String? { pomodoro.errorMessage }
  var timerBusy: Bool { pomodoro.isBusy }

  func toggleTimer() async { await pomodoro.toggle() }
  func resetTimer() async { await pomodoro.reset() }

  // MARK: - Panels

  /// Whether the first state arrived (cache or server).
  var hasState: Bool { dashboard.state != nil }

  /// `nothingOn` (`useDashboardPanels.tsx:48`).
  var nothingOn: Bool { dashboard.state?.modules.isEmpty ?? false }

  /// The modules that are on, in the web's panel order.
  var modules: [ModuleID] {
    let enabled = dashboard.state?.modules ?? []
    return ModuleID.known.filter(enabled.contains)
  }

  /// Nil until the first state arrives (cache or server).
  func panels(at now: Date) -> HomePanels? {
    dashboard.state.map { HomePanels(state: $0, now: now) }
  }

  /// Each summary panel's chosen tab, by module. Kept here and not in the panel's
  /// view so it survives the panel's view being rebuilt.
  private var selectedTabs: [ModuleID: String] = [:]

  /// The chosen tab while the panel still has it, else the panel's first tab.
  func selectedTab(of panel: HomePanel) -> HomeTab? {
    panel.tabs.first { $0.id == selectedTabs[panel.module] } ?? panel.tabs.first
  }

  func selectTab(_ tabID: String, of module: ModuleID) {
    selectedTabs[module] = tabID
  }

  // MARK: - Grade / Abas

  var homeView: HomeView { layoutStore.homeView }
  /// A value this version does not know shows the grid, the web's default.
  var showsTabs: Bool { homeView == .workspace }
  /// The switch only makes sense with something to arrange (`page.tsx:114`).
  var showsViewSwitch: Bool { hasState && !nothingOn }

  /// "Grade" / "Abas" (`page.tsx:78-95`): the screen changes at once and goes
  /// back with "Não deu para trocar a disposição" if the server refuses.
  func chooseView(_ view: HomeView) async {
    if view != homeView { discardArrangement() }
    await layoutStore.setHomeView(view)
  }

  /// The grid's save failure, else the tabs' own.
  var layoutError: String? { layoutStore.layoutError ?? workspace.saveError }
  var viewError: String? { layoutStore.viewError }

  // MARK: - Grid

  func updateWindowSize(_ size: CGSize) {
    guard size != windowSize else { return }
    windowSize = size
    if grid.isArranging, isNarrow {
      // The narrow grid cannot be arranged; leaving the mode keeps nothing stuck.
      grid.discard()
    }
    if !grid.isArranging { layoutSize = size }
  }

  var isWindowMeasured: Bool { windowSize.width > 0 && windowSize.height > 0 }
  var isNarrow: Bool { NarrowDashboard.isNarrow(width: windowSize.width) }

  /// Every panel's place for the current window (`page.tsx:47-50`): the layout
  /// saved for the nearest size, else the legacy one, else the default; sanitized.
  var fullLayout: [PanelPlacement] {
    DashboardLayoutEngine.layout(
      saved: layoutStore.layouts, legacy: layoutStore.layout,
      width: Double(layoutSize.width), height: Double(layoutSize.height))
  }

  /// The panels of the modules that are on, as the grid draws them.
  var shownLayout: [PanelPlacement] {
    DashboardLayoutEngine.synchronize(DashboardLayoutEngine.layoutFor(fullLayout, enabled: modules))
  }

  /// What the grid draws now: the arrange draft, else `shownLayout`.
  var gridLayout: [PanelPlacement] { grid.displayed(shownLayout) }

  /// Whether "Organizar painéis" can start: the wide grid is on screen with panels.
  public var canArrange: Bool {
    !showsTabs && showsViewSwitch && isWindowMeasured && !isNarrow && !grid.isArranging
  }

  /// "Organizar painéis" in the View menu, and holding a panel for 0.5 s.
  public func beginArranging() {
    guard canArrange else { return }
    grid.begin()
  }

  func movePanel(_ module: ModuleID, x: Int, y: Int) {
    grid.move(module, x: x, y: y, shown: shownLayout)
  }

  func resizePanel(_ module: ModuleID, w: Int, h: Int) {
    grid.resize(module, w: w, h: h, shown: shownLayout)
  }

  func discardArrangement() {
    guard grid.isArranging else { return }
    grid.discard()
    layoutSize = windowSize
  }

  /// "Salvar para esta tela": saved for the window's size right now.
  func saveArrangement() async {
    await grid.save(full: fullLayout, viewport: windowSize)
    layoutSize = windowSize
  }

  // MARK: - Narrow grid

  /// The modules of the narrow grid, in reading order of the layout.
  var narrowModules: [ModuleID] { NarrowDashboard.modules(shownLayout) }

  var activeNarrowModule: ModuleID? {
    NarrowDashboard.active(selected: narrowSelection, modules: narrowModules)
  }

  func selectNarrowModule(_ module: ModuleID) {
    narrowSelection = module
  }

  // MARK: - Abas

  /// Whose arrangement the tabs read and write; nil without a server or user.
  var workspaceAccount: LayoutAccount? {
    guard let server = session.serverURL, let user = session.user else { return nil }
    return LayoutAccount(server: server, username: user.username)
  }

  func loadWorkspace() {
    workspace.load(account: workspaceAccount, modules: modules)
  }

  func reconcileWorkspace() {
    workspace.reconcile(modules: modules)
  }

  /// "Restaurar abas".
  func restoreWorkspace() {
    workspace.restore(modules: modules)
  }
}
