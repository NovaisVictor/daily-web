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
  /// The last layouts computed, with what they were computed from.
  @ObservationIgnored private var layoutCache: LayoutCache?

  private struct LayoutInputs: Equatable {
    var saved: [SavedLayout]
    var legacy: [LayoutItem]
    var size: CGSize
    var modules: [ModuleID]
  }

  private struct LayoutCache {
    var inputs: LayoutInputs
    var full: [PanelPlacement]
    var shown: [PanelPlacement]
  }

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
  var fullLayout: [PanelPlacement] { layouts().full }

  /// The panels of the modules that are on, as the grid draws them.
  var shownLayout: [PanelPlacement] { layouts().shown }

  /// What the grid draws now: the gesture's preview or the arrange draft,
  /// else `shownLayout`.
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

  /// One pointer event of a move or resize; true when the panel's target
  /// cell or size changed.
  @discardableResult
  func dragPanel(
    _ module: ModuleID, kind: GridDragSession.Kind, startLocation: CGPoint, translation: CGSize,
    containerWidth: CGFloat
  ) -> Bool {
    grid.drag(
      module, kind: kind, startLocation: startLocation, translation: translation,
      containerWidth: containerWidth, shown: shownLayout)
  }

  func endPanelGesture() {
    grid.endGesture()
  }

  func cancelPanelGesture() {
    grid.cancelGesture()
  }

  func movePanel(_ module: ModuleID, x: Int, y: Int) {
    grid.move(module, x: x, y: y, shown: shownLayout)
  }

  func resizePanel(_ module: ModuleID, w: Int, h: Int) {
    grid.resize(module, w: w, h: h, shown: shownLayout)
  }

  /// The arrows while arranging: one step of the focused panel, or with
  /// Shift one row or column more or less of its size.
  func nudgePanel(_ module: ModuleID, dx: Int, dy: Int, resizing: Bool) {
    if resizing {
      guard let placement = gridLayout.first(where: { $0.i == module }) else { return }
      resizePanel(module, w: placement.w + dx, h: placement.h + dy)
    } else {
      grid.nudge(module, dx: dx, dy: dy, shown: shownLayout)
    }
  }

  /// Esc while arranging, heard anywhere in the window (`DashboardGrid.tsx:261-269`).
  /// A gesture in progress is the nearer thing to undo, so the first Esc only
  /// cancels it; with none, the mode is discarded.
  func escapeArrangement() {
    guard !grid.cancelGesture() else { return }
    discardArrangement()
  }

  func discardArrangement() {
    guard grid.isArranging else { return }
    grid.discard()
    layoutSize = windowSize
  }

  /// "Salvar para esta tela": saved for the window's size right now.
  func saveArrangement() async {
    await grid.save(full: fullLayout, viewport: windowSize)
    // Arranging again while the server answered keeps that mode's layout size.
    if !grid.isArranging { layoutSize = windowSize }
  }

  /// "Concluir organização" in the View menu: the same as saving.
  func finishArranging() async {
    guard grid.isArranging, !grid.isSaving else { return }
    await saveArrangement()
  }

  /// What the View menu shows for this window (`focusedSceneValue`).
  var arrangeMenu: HomeArrangeMenu {
    HomeArrangeMenu(isArranging: grid.isArranging, isSaving: grid.isSaving) { [self] in
      Task { await finishArranging() }
    }
  }

  /// `fullLayout` and `shownLayout`, computed again only when what they are
  /// made of changes: the grid reads them on every redraw, and parsing every
  /// saved size to find the nearest is not free.
  private func layouts() -> (full: [PanelPlacement], shown: [PanelPlacement]) {
    let inputs = LayoutInputs(
      saved: home.layoutStore.layouts, legacy: home.layoutStore.layout, size: layoutSize, modules: home.modules)
    if let layoutCache, layoutCache.inputs == inputs { return (layoutCache.full, layoutCache.shown) }
    let full = DashboardLayoutEngine.layout(
      saved: inputs.saved, legacy: inputs.legacy, width: Double(inputs.size.width),
      height: Double(inputs.size.height))
    let shown = DashboardLayoutEngine.synchronize(DashboardLayoutEngine.layoutFor(full, enabled: inputs.modules))
    layoutCache = LayoutCache(inputs: inputs, full: full, shown: shown)
    return (full, shown)
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
