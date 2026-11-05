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
/// One per session: what every window shows alike. What one window does with
/// it (its size, the arrange mode, the narrow grid's module) is that window's
/// `HomeWindowState`, so two main windows never fight over it.
@Observable
public final class HomeStore {
  static let storeKey = "home"

  @ObservationIgnored private let session: SessionStore
  @ObservationIgnored private let dashboard: DashboardStore
  @ObservationIgnored private let pomodoro: PomodoroController
  @ObservationIgnored private let poller: Poller?
  @ObservationIgnored let layoutStore: DashboardLayoutStore
  let workspace: HomeWorkspace

  init(
    session: SessionStore, dashboard: DashboardStore, pomodoro: PomodoroController,
    layoutStore: DashboardLayoutStore, poller: Poller? = nil, sleep: @escaping Sleeper = LiveTime.sleep
  ) {
    self.session = session
    self.dashboard = dashboard
    self.pomodoro = pomodoro
    self.poller = poller
    self.layoutStore = layoutStore
    workspace = HomeWorkspace(store: layoutStore, sleep: sleep)
  }

  convenience init(environment: AppEnvironment, workspaceDirectory: URL?) {
    let layoutStore = DashboardLayoutStore.shared(in: environment, workspaceDirectory: workspaceDirectory)
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
    await layoutStore.setHomeView(view)
  }

  /// The grid's save failure, else the tabs' own.
  var layoutError: String? { layoutStore.layoutError ?? workspace.saveError }
  var viewError: String? { layoutStore.viewError }

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
    workspace.restore(account: workspaceAccount, modules: modules)
  }
}
