import CoreGraphics
import DailyAPI
import DailyCore
import DailyModels
import Observation

/// The grid's arrange mode (`components/DashboardGrid.tsx`): holding a panel
/// (or Visualizar → Organizar painéis) turns it on, dragging and resizing
/// change a draft, and only "Salvar para esta tela" sends it to the server.
/// "Descartar" and Esc drop the draft.
@Observable
final class GridArrangement {
  private(set) var isArranging = false
  /// What was moved or resized and not saved yet (`rascunho`). While it
  /// exists the grid draws it instead of the saved layout.
  private(set) var draft: [PanelPlacement]?
  private(set) var isSaving = false
  /// The panel being moved or resized: it stays still while the others jiggle.
  private(set) var activePanel: ModuleID?

  @ObservationIgnored private let layoutStore: DashboardLayoutStore
  /// The last grid cell a gesture asked for. A dragged panel that compacts
  /// upward would otherwise be moved again on every pointer event.
  @ObservationIgnored private var lastTarget: Target?

  private struct Target: Equatable {
    var module: ModuleID
    var isResize: Bool
    var a: Int
    var b: Int
  }

  init(layoutStore: DashboardLayoutStore) {
    self.layoutStore = layoutStore
  }

  func begin() {
    guard !isArranging else { return }
    isArranging = true
    draft = nil
    lastTarget = nil
  }

  /// The layout the grid draws: the draft while there is one, else `shown`.
  func displayed(_ shown: [PanelPlacement]) -> [PanelPlacement] {
    draft ?? shown
  }

  /// Marks the panel a gesture is on, or none when the gesture ends.
  func setActive(_ module: ModuleID?) {
    activePanel = module
    if module == nil { lastTarget = nil }
  }

  /// Drops `module` on grid cell `(x, y)`; the others make room and compact,
  /// as `react-grid-layout` does while dragging.
  func move(_ module: ModuleID, x: Int, y: Int, shown: [PanelPlacement]) {
    guard isArranging else { return }
    let target = Target(module: module, isResize: false, a: x, b: y)
    guard target != lastTarget else { return }
    lastTarget = target
    let current = draft ?? shown
    guard let placement = current.first(where: { $0.i == module }) else { return }
    guard placement.x != x || placement.y != y else { return }
    draft = DashboardLayoutEngine.move(current, id: module, x: x, y: y)
  }

  /// Resizes `module` from its south-east corner to `w` × `h` grid units.
  func resize(_ module: ModuleID, w: Int, h: Int, shown: [PanelPlacement]) {
    guard isArranging else { return }
    let target = Target(module: module, isResize: true, a: w, b: h)
    guard target != lastTarget else { return }
    lastTarget = target
    let current = draft ?? shown
    guard let placement = current.first(where: { $0.i == module }) else { return }
    guard placement.w != w || placement.h != h else { return }
    draft = DashboardLayoutEngine.resize(current, id: module, w: w, h: h)
  }

  /// "Descartar" and Esc (`descartar`): nothing was saved, so nothing to undo.
  func discard() {
    draft = nil
    isArranging = false
    activePanel = nil
    lastTarget = nil
  }

  /// "Salvar para esta tela" (`salvar`, `DashboardGrid.tsx:113-130`). Without
  /// a draft, pinning the layout on screen to this size is still a choice, so
  /// `full` is saved; a draft is completed with the default places of the
  /// panels it does not show, as the web's `parseLayout` does. The mode ends
  /// either way; a failure is the store's `layoutError`.
  @discardableResult
  func save(full: [PanelPlacement], viewport: CGSize) async -> APIError? {
    guard isArranging, !isSaving else { return nil }
    isSaving = true
    let layout = draft.map { DashboardLayoutEngine.parseLayout($0.map(\.layoutItem)) } ?? full
    let error = await layoutStore.saveGrid(DashboardLayoutEngine.serializeLayout(layout), viewport: viewport)
    isSaving = false
    discard()
    return error
  }
}

/// The narrow grid (`DashboardGrid.tsx:296-341`): one module at a time, chosen
/// in a bar at the bottom.
nonisolated enum NarrowDashboard {
  /// Panels in reading order: top to bottom, then left to right.
  static func modules(_ layout: [PanelPlacement]) -> [ModuleID] {
    layout.enumerated()
      .sorted { left, right in
        if left.element.y != right.element.y { return left.element.y < right.element.y }
        if left.element.x != right.element.x { return left.element.x < right.element.x }
        return left.offset < right.offset
      }
      .map(\.element.i)
  }

  /// The chosen module while it is still shown, else the first.
  static func active(selected: ModuleID?, modules: [ModuleID]) -> ModuleID? {
    if let selected, modules.contains(selected) { return selected }
    return modules.first
  }

  /// One module at a time only pays off with two or more; fewer are stacked.
  static func showsBar(modules: [ModuleID]) -> Bool {
    modules.count >= 2
  }

  /// `(max-width: 1023px)`: the web counts 1023 itself as narrow.
  static func isNarrow(width: CGFloat) -> Bool {
    width > 0 && width <= DashboardLayoutEngine.narrowBreakpoint
  }
}
