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
  /// exists the grid draws it instead of the saved layout. A gesture only
  /// writes it when the pointer is released.
  private(set) var draft: [PanelPlacement]?
  private(set) var isSaving = false
  /// The move or resize in progress. Only replaced when it really changes, so
  /// a pointer event that keeps the target does not redraw the grid.
  private(set) var tracker = GridGestureTracker()
  /// How far the pointer carried the panel under the gesture.
  let pointer = GridPointer()

  @ObservationIgnored private let layoutStore: DashboardLayoutStore
  /// Bumped whenever the mode starts or ends, so a save that answers late
  /// only ends the mode it was started from.
  @ObservationIgnored private var generation = 0

  init(layoutStore: DashboardLayoutStore) {
    self.layoutStore = layoutStore
  }

  var session: GridDragSession? { tracker.session }

  /// The panel being moved or resized: it stays still while the others jiggle.
  var activePanel: ModuleID? { tracker.session?.module }

  func begin() {
    guard !isArranging else { return }
    isArranging = true
    draft = nil
    generation += 1
    resetGesture()
  }

  /// The layout the grid draws: the gesture's preview, else the draft, else `shown`.
  func displayed(_ shown: [PanelPlacement]) -> [PanelPlacement] {
    tracker.session?.preview ?? draft ?? shown
  }

  /// One pointer event of a move or resize of `module`. True when the
  /// panel's target cell or size changed, the moment a haptic tap belongs to.
  @discardableResult
  func drag(
    _ module: ModuleID, kind: GridDragSession.Kind, startLocation: CGPoint, translation: CGSize,
    containerWidth: CGFloat, shown: [PanelPlacement]
  ) -> Bool {
    guard isArranging, !isSaving else { return false }
    if let current = tracker.session, !current.belongs(module: module, kind: kind, startLocation: startLocation) {
      // The previous gesture's end was never heard; what it did still counts.
      endGesture()
    }
    var next = tracker
    let outcome = next.update(
      module: module, kind: kind, startLocation: startLocation, translation: translation,
      layout: draft ?? shown, containerWidth: containerWidth)
    if next != tracker { tracker = next }
    guard outcome != .ignored else { return false }
    pointer.update(translation)
    return outcome == .changed
  }

  /// The pointer was released: the gesture's layout becomes the draft.
  func endGesture() {
    var next = tracker
    let left = next.end()
    if next != tracker { tracker = next }
    if let left { draft = left }
    pointer.update(.zero)
  }

  /// Esc during a gesture puts the panel back where the gesture found it and
  /// keeps the mode. False when no gesture was in progress.
  @discardableResult
  func cancelGesture() -> Bool {
    var next = tracker
    guard next.cancel() else { return false }
    tracker = next
    pointer.update(.zero)
    return true
  }

  /// Drops `module` on grid cell `(x, y)`; the others make room and compact,
  /// as `react-grid-layout` does while dragging. The keyboard's way to move.
  func move(_ module: ModuleID, x: Int, y: Int, shown: [PanelPlacement]) {
    guard isArranging, tracker.session == nil else { return }
    let current = draft ?? shown
    guard let placement = current.first(where: { $0.i == module }) else { return }
    guard placement.x != x || placement.y != y else { return }
    draft = DashboardLayoutEngine.move(current, id: module, x: x, y: y)
  }

  /// Resizes `module` from its south-east corner to `w` × `h` grid units.
  func resize(_ module: ModuleID, w: Int, h: Int, shown: [PanelPlacement]) {
    guard isArranging, tracker.session == nil else { return }
    let current = draft ?? shown
    guard let placement = current.first(where: { $0.i == module }) else { return }
    guard placement.w != w || placement.h != h else { return }
    draft = DashboardLayoutEngine.resize(current, id: module, w: w, h: h)
  }

  /// Moves `module` one step from the keyboard (`DashboardLayoutEngine.nudge`).
  func nudge(_ module: ModuleID, dx: Int, dy: Int, shown: [PanelPlacement]) {
    guard isArranging, tracker.session == nil else { return }
    let current = draft ?? shown
    let moved = DashboardLayoutEngine.nudge(current, id: module, dx: dx, dy: dy)
    if moved != current { draft = moved }
  }

  /// "Descartar" and Esc (`descartar`): nothing was saved, so nothing to undo.
  func discard() {
    draft = nil
    isArranging = false
    generation += 1
    resetGesture()
  }

  /// "Salvar para esta tela" (`salvar`, `DashboardGrid.tsx:113-130`). Without
  /// a draft, pinning the layout on screen to this size is still a choice, so
  /// `full` is saved; a draft is laid over `full`. The mode ends either way; a
  /// failure is the store's `layoutError`. A gesture in progress counts as
  /// released, so what is on screen is what gets saved.
  @discardableResult
  func save(full: [PanelPlacement], viewport: CGSize) async -> APIError? {
    guard isArranging, !isSaving else { return nil }
    endGesture()
    isSaving = true
    let started = generation
    let layout = draft.map { Self.merge($0, over: full) } ?? full
    let error = await layoutStore.saveGrid(DashboardLayoutEngine.serializeLayout(layout), viewport: viewport)
    isSaving = false
    // Discarded while the server answered, and maybe arranging again since:
    // that is a newer mode, which this save must not end.
    if generation == started { discard() }
    return error
  }

  private func resetGesture() {
    var cleared = tracker
    cleared.reset()
    if cleared != tracker { tracker = cleared }
    pointer.update(.zero)
  }

  /// The draft's places over `full`. The web completes a draft with
  /// `parseLayout`, which sends the panels of modules that are off back to
  /// their default places; keeping their saved places means turning a module
  /// back on finds it where it was.
  static func merge(_ draft: [PanelPlacement], over full: [PanelPlacement]) -> [PanelPlacement] {
    var moved: [ModuleID: PanelPlacement] = [:]
    for placement in draft where moved[placement.i] == nil {
      moved[placement.i] = placement
    }
    let merged = full.map { moved.removeValue(forKey: $0.i) ?? $0 }
    return merged + draft.filter { moved[$0.i] != nil }
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

/// The arrange mode from the keyboard, which the web does not have: Tab goes
/// through the panels in reading order, the arrows move or resize the
/// focused one.
nonisolated enum GridKeyboard {
  /// The panel after `module` in reading order, wrapping around; the first
  /// when `module` is not shown.
  static func next(after module: ModuleID?, in layout: [PanelPlacement], backwards: Bool) -> ModuleID? {
    let order = NarrowDashboard.modules(layout)
    guard !order.isEmpty else { return nil }
    guard let module, let index = order.firstIndex(of: module) else { return order.first }
    let step = backwards ? order.count - 1 : 1
    return order[(index + step) % order.count]
  }
}
