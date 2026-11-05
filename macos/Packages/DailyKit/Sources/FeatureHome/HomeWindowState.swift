import CoreGraphics
import DailyCore
import DailyModels
import Observation

/// What one window's Início does with the session's `HomeStore`: the window's
/// size, the grid chosen for it, the arrange mode and the narrow grid's module.
/// Each `HomeScreen` owns one, so two main windows arrange and choose apart.
@Observable
final class HomeWindowState {
  let home: HomeStore
  let grid: GridArrangement

  /// The window's content size, as the web's `window.innerWidth/innerHeight`.
  private(set) var windowSize: CGSize = .zero
  /// The size the grid layout is chosen for. It stays put while arranging, so
  /// resizing the window then does not swap the layout under the draft.
  private var layoutSize: CGSize = .zero
  /// The module the narrow grid shows, as the web's `?modulo=`.
  private var narrowSelection: ModuleID?

  init(home: HomeStore) {
    self.home = home
    grid = GridArrangement(layoutStore: home.layoutStore)
  }

  // MARK: - Window

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

  // MARK: - Grid

  /// Every panel's place for this window (`page.tsx:47-50`): the layout saved
  /// for the nearest size, else the legacy one, else the default; sanitized.
  var fullLayout: [PanelPlacement] {
    DashboardLayoutEngine.layout(
      saved: home.layoutStore.layouts, legacy: home.layoutStore.layout,
      width: Double(layoutSize.width), height: Double(layoutSize.height))
  }

  /// The panels of the modules that are on, as the grid draws them.
  var shownLayout: [PanelPlacement] {
    DashboardLayoutEngine.synchronize(DashboardLayoutEngine.layoutFor(fullLayout, enabled: home.modules))
  }

  /// What the grid draws now: the arrange draft, else `shownLayout`.
  var gridLayout: [PanelPlacement] { grid.displayed(shownLayout) }

  /// Whether "Organizar painéis" can start: the wide grid is on screen with panels.
  var canArrange: Bool {
    !home.showsTabs && home.showsViewSwitch && isWindowMeasured && !isNarrow && !grid.isArranging
  }

  /// "Organizar painéis" in the View menu, and holding a panel for 0.5 s.
  func beginArranging() {
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

  /// "Grade" / "Abas" from this window: its draft goes, since the grid it
  /// belongs to stops showing.
  func chooseView(_ view: HomeView) async {
    if view != home.homeView { discardArrangement() }
    await home.chooseView(view)
  }

  // MARK: - "Organizar painéis" from the menu

  /// Answers the View menu's request when this window is the key one. The
  /// request waits while the answer is not known yet (no state, or the grid's
  /// size not measured); it is taken, and does nothing, where the grid cannot
  /// be arranged (tabs, nothing on, a narrow window), so it never starts
  /// arranging later by surprise.
  func handleArrangeRequest(from navigator: AppNavigator, isKeyWindow: Bool) {
    guard isKeyWindow, navigator.isArrangeRequested, home.hasState else { return }
    let canAnswer = home.showsTabs || home.nothingOn || isWindowMeasured
    guard canAnswer, navigator.takeArrangeRequest() else { return }
    beginArranging()
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
}
