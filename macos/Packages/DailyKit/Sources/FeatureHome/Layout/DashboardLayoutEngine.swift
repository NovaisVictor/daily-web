import CoreGraphics
import DailyModels
import Foundation

/// Where one panel sits on the home grid, in grid units (`PanelPlacement`,
/// `lib/dashboardLayout.ts:8-15`).
public nonisolated struct PanelPlacement: Sendable, Equatable, Hashable, Codable {
  /// The panel's module; the web calls it `i`.
  public var i: ModuleID
  public var x: Int
  public var y: Int
  public var w: Int
  public var h: Int

  public init(i: ModuleID, x: Int, y: Int, w: Int, h: Int) {
    self.i = i
    self.x = x
    self.y = y
    self.w = w
    self.h = h
  }

  /// The server's shape, as `PATCH /api/preferences {layout}` expects it.
  public var layoutItem: LayoutItem {
    LayoutItem(i: i.rawValue, x: Double(x), y: Double(y), w: Double(w), h: Double(h))
  }

  /// The same cleaning as the web's `sanitize` (`lib/dashboardLayout.ts:52-70`):
  /// nil for an unknown module or a non-finite number, every value clamped
  /// into the grid otherwise.
  public init?(_ item: LayoutItem) {
    guard let placement = DashboardLayoutEngine.sanitize(item) else { return nil }
    self = placement
  }
}

/// A grid cell: where a panel's top-left corner sits, in grid units.
public nonisolated struct GridCell: Sendable, Equatable, Hashable {
  public var x: Int
  public var y: Int

  public init(x: Int, y: Int) {
    self.x = x
    self.y = y
  }
}

/// A panel's size in grid units.
public nonisolated struct GridSpan: Sendable, Equatable, Hashable {
  public var w: Int
  public var h: Int

  public init(w: Int, h: Int) {
    self.w = w
    self.h = h
  }
}

/// A grid layout saved for one window size (`SizedLayout`, `lib/dashboardLayout.ts:107-111`).
public nonisolated struct SizedLayout: Sendable, Equatable, Hashable {
  public var width: Int
  public var height: Int
  public var layout: [PanelPlacement]

  public init(width: Int, height: Int, layout: [PanelPlacement]) {
    self.width = width
    self.height = height
    self.layout = layout
  }

  public var savedLayout: SavedLayout {
    SavedLayout(width: Double(width), height: Double(height), layout: layout.map(\.layoutItem))
  }
}

/// The home grid's rules: the web's `lib/dashboardLayout.ts` plus the parts of
/// `react-grid-layout` 2.3.0 the web grid relies on (vertical compaction,
/// moving with collisions, resizing from the south-east handle). Pure, so the
/// view only turns gestures into grid units and draws the result.
public nonisolated enum DashboardLayoutEngine {
  public static let columns = 12
  /// Height of one grid row, in points (`GRID_ROW_HEIGHT`).
  public static let rowHeight: CGFloat = 32
  /// Gap between panels, both ways (`DashboardGrid.tsx:277`).
  public static let margin: CGFloat = 24
  public static let minimumWidth = 3
  public static let minimumHeight = 4
  public static let maximumHeight = 80
  /// Below this content width the grid shows one module at a time (`NARROW_BREAKPOINT`).
  public static let narrowBreakpoint: CGFloat = 1023
  /// How many window sizes keep a layout (`MAX_SIZED_LAYOUTS`).
  public static let maximumSizedLayouts = 20
  /// No real layout goes this far down. Bounding `y` keeps a doctored value
  /// from trapping on the conversion to `Int`; the web keeps any finite `y`.
  static let maximumY = 100_000

  /// The panels the grid places, in the web's default order (`lib/dashboardLayout.ts:34-42`).
  /// E-mail and tasks in the wide column; agenda, Jira and pull requests in the narrow one.
  public static func defaultLayout() -> [PanelPlacement] {
    [
      PanelPlacement(i: .email, x: 0, y: 0, w: 7, h: 14),
      PanelPlacement(i: .tasks, x: 0, y: 14, w: 7, h: 12),
      PanelPlacement(i: .agenda, x: 7, y: 0, w: 5, h: 9),
      PanelPlacement(i: .jira, x: 7, y: 9, w: 5, h: 12),
      PanelPlacement(i: .pulls, x: 7, y: 21, w: 5, h: 5),
      PanelPlacement(i: .notes, x: 0, y: 26, w: 7, h: 10),
      PanelPlacement(i: .slack, x: 7, y: 26, w: 5, h: 10),
    ]
  }

  // MARK: - Reading what the server saved

  /// `sanitize` (`lib/dashboardLayout.ts:52-70`). A doctored or stale value can
  /// neither push the panel off screen nor make it absurdly tall.
  public static func sanitize(_ item: LayoutItem) -> PanelPlacement? {
    let module = ModuleID(rawValue: item.i)
    guard ModuleID.known.contains(module) else { return nil }
    guard [item.x, item.y, item.w, item.h].allSatisfy(\.isFinite) else { return nil }
    let w = min(max(jsRound(item.w), Double(minimumWidth)), Double(columns))
    let x = min(max(jsRound(item.x), 0), Double(columns) - w)
    let y = min(max(jsRound(item.y), 0), Double(maximumY))
    let h = min(max(jsRound(item.h), Double(minimumHeight)), Double(maximumHeight))
    return PanelPlacement(i: module, x: Int(x), y: Int(y), w: Int(w), h: Int(h))
  }

  /// `parseLayout` (`lib/dashboardLayout.ts:77-87`): always one placement per
  /// panel, in the default order. A panel missing from what was saved (added in
  /// a later version) takes its default place instead of disappearing.
  public static func parseLayout(_ items: [LayoutItem]) -> [PanelPlacement] {
    var saved: [ModuleID: PanelPlacement] = [:]
    for item in items {
      if let placement = sanitize(item) { saved[placement.i] = placement }
    }
    return defaultLayout().map { saved[$0.i] ?? $0 }
  }

  /// `serializeLayout` (`lib/dashboardLayout.ts:89-95`): only valid placements, cleaned.
  public static func serializeLayout(_ layout: [PanelPlacement]) -> [LayoutItem] {
    layout.compactMap { sanitize($0.layoutItem) }.map(\.layoutItem)
  }

  /// `layoutFor` (`lib/dashboardLayout.ts:98-100`): only the panels of enabled modules.
  public static func layoutFor(_ layout: [PanelPlacement], enabled: [ModuleID]) -> [PanelPlacement] {
    layout.filter { enabled.contains($0.i) }
  }

  /// `isDefaultLayout` (`lib/dashboardLayout.ts:102-104`).
  public static func isDefaultLayout(_ layout: [PanelPlacement]) -> Bool {
    serializeLayout(layout) == serializeLayout(defaultLayout())
  }

  /// `parseSizedLayouts` (`lib/dashboardLayout.ts:124-139`): drops sizes that
  /// match no window, keeps the first of two equal sizes, at most 20.
  public static func parseSizedLayouts(_ entries: [SavedLayout]) -> [SizedLayout] {
    var result: [SizedLayout] = []
    for entry in entries {
      guard entry.width.isFinite, entry.height.isFinite, entry.width > 0, entry.height > 0 else { continue }
      let width = pixels(entry.width)
      let height = pixels(entry.height)
      if result.contains(where: { $0.width == width && $0.height == height }) { continue }
      result.append(SizedLayout(width: width, height: height, layout: parseLayout(entry.layout)))
    }
    return Array(result.prefix(maximumSizedLayouts))
  }

  /// `putSizedLayout` (`lib/dashboardLayout.ts:156-167`): saving again at the
  /// same size replaces; a new size goes first and the oldest falls off past 20.
  public static func putSizedLayout(
    _ entries: [SizedLayout], width: Double, height: Double, layout: [PanelPlacement]
  ) -> [SizedLayout] {
    let others = entries.filter { !($0.width == pixels(width) && $0.height == pixels(height)) }
    let entry = SizedLayout(width: pixels(width), height: pixels(height), layout: layout)
    return Array(([entry] + others).prefix(maximumSizedLayouts))
  }

  /// `nearestLayout` (`lib/dashboardLayout.ts:179-194`): Euclidean distance on
  /// width and height, no maximum. A tie goes to the first, the newest.
  public static func nearestLayout(_ entries: [SizedLayout], width: Double, height: Double) -> SizedLayout? {
    var best: SizedLayout?
    var shortest = Double.infinity
    for entry in entries {
      let distance = hypot(Double(entry.width) - width, Double(entry.height) - height)
      if distance < shortest {
        shortest = distance
        best = entry
      }
    }
    return best
  }

  /// What the home grid shows for a window (`app/(app)/page.tsx:32-51`): the
  /// layout saved for the nearest size, else the single legacy layout.
  public static func layout(
    saved: [SavedLayout], legacy: [LayoutItem], width: Double, height: Double
  ) -> [PanelPlacement] {
    nearestLayout(parseSizedLayouts(saved), width: width, height: height)?.layout ?? parseLayout(legacy)
  }

  // MARK: - Arranging (react-grid-layout, `compactType: vertical`)

  /// What the grid draws for a layout it is handed (`synchronizeLayoutWithChildren`):
  /// panels pulled back inside the columns, then compacted upward.
  public static func synchronize(_ layout: [PanelPlacement]) -> [PanelPlacement] {
    var nodes = layout.map(Node.init)
    for index in nodes.indices {
      if nodes[index].x + nodes[index].w > columns { nodes[index].x = columns - nodes[index].w }
      if nodes[index].x < 0 {
        nodes[index].x = 0
        nodes[index].w = columns
      }
    }
    return compact(nodes).map(\.placement)
  }

  /// `verticalCompactor.compact`: every panel rises as far as it can without
  /// overlapping one above it; overlaps are pushed down. Keeps the input order.
  public static func compact(_ layout: [PanelPlacement]) -> [PanelPlacement] {
    compact(layout.map(Node.init)).map(\.placement)
  }

  /// Drops panel `id` at `(x, y)`, as the end of a drag does (`onDragStop`):
  /// the position is kept inside the columns, the panels it lands on move down,
  /// and the whole layout compacts.
  public static func move(_ layout: [PanelPlacement], id: ModuleID, x: Int, y: Int) -> [PanelPlacement] {
    var nodes = layout.map(Node.init)
    guard let index = nodes.firstIndex(where: { $0.i == id }) else { return layout }
    let w = nodes[index].w
    // `calcXY` clamps the drop to the grid before `moveElement` sees it.
    let clampedX = min(max(x, 0), max(0, columns - w))
    let clampedY = max(y, 0)
    moveElement(&nodes, id: id, x: clampedX, y: clampedY, isUserAction: true)
    return compact(nodes).map(\.placement)
  }

  /// Resizes panel `id` from its south-east corner, the only handle the web
  /// offers (`DashboardGrid.tsx:291-294`, `onResize`): the size is clamped to
  /// the grid and to the panel limits, then the layout compacts, which pushes
  /// the panels it now covers down.
  public static func resize(_ layout: [PanelPlacement], id: ModuleID, w: Int, h: Int) -> [PanelPlacement] {
    var nodes = layout.map(Node.init)
    guard let index = nodes.firstIndex(where: { $0.i == id }) else { return layout }
    // `gridBounds` then `minMaxSize` (`constraints.ts`). The web sets no
    // `maxH` on the grid; the 80 rows `sanitize` enforces on save are applied
    // here too so what is shown is what gets saved.
    let maximumW = max(1, columns - nodes[index].x)
    nodes[index].w = max(min(max(w, 1), maximumW), minimumWidth)
    nodes[index].h = min(max(h, minimumHeight), maximumHeight)
    return compact(nodes).map(\.placement)
  }

  /// How many rows the layout uses (`bottom`).
  public static func bottom(_ layout: [PanelPlacement]) -> Int {
    layout.map { $0.y + $0.h }.max() ?? 0
  }

  // MARK: - Points (`calculate.ts`)

  /// Width of one column for a container (`calcGridColWidth`, no container padding).
  public static func columnWidth(containerWidth: CGFloat) -> CGFloat {
    (containerWidth - margin * CGFloat(columns - 1)) / CGFloat(columns)
  }

  /// Where a placement is drawn (`calcGridItemPosition`), rounded to whole points.
  public static func frame(for placement: PanelPlacement, containerWidth: CGFloat) -> CGRect {
    let column = columnWidth(containerWidth: containerWidth)
    let left = ((column + margin) * CGFloat(placement.x)).rounded()
    let top = ((rowHeight + margin) * CGFloat(placement.y)).rounded()
    // Measuring to the next panel's edge keeps the gaps exact despite rounding.
    let right = ((column + margin) * CGFloat(placement.x + placement.w)).rounded() - margin
    let bottom = ((rowHeight + margin) * CGFloat(placement.y + placement.h)).rounded() - margin
    return CGRect(x: left, y: top, width: right - left, height: bottom - top)
  }

  // MARK: - Following the pointer

  /// How far, in cells, a panel has to be carried from the cell it is on
  /// before it switches cells. `calcXY` rounds, which switches at half a cell:
  /// a pointer resting near that edge flipped the cell, and every panel with
  /// it, back and forth. Past 0.6, a band of 0.2 cell holds the current one.
  public static let cellSwitchDistance = 0.6

  /// The grid cell a panel `w` columns wide dragged to `origin` lands on
  /// (`calcXY`), staying on `previous` until it is carried far enough away.
  public static func cell(for origin: CGPoint, w: Int, containerWidth: CGFloat, previous: GridCell?) -> GridCell {
    let column = columnWidth(containerWidth: containerWidth)
    let x = snap(Double(origin.x / (column + margin)), previous: previous?.x)
    let y = snap(Double(origin.y / (rowHeight + margin)), previous: previous?.y)
    return GridCell(x: min(max(x, 0), max(0, columns - w)), y: min(max(y, 0), maximumY))
  }

  /// The grid size a panel at column `x` takes when resized to `size`
  /// (`calcWH`), with the same hold as `cell(for:)` and the limits `resize`
  /// applies, so the size reported is the size drawn.
  public static func span(for size: CGSize, x: Int, containerWidth: CGFloat, previous: GridSpan?) -> GridSpan {
    let column = columnWidth(containerWidth: containerWidth)
    let w = snap(Double((size.width + margin) / (column + margin)), previous: previous?.w)
    let h = snap(Double((size.height + margin) / (rowHeight + margin)), previous: previous?.h)
    return GridSpan(
      w: max(min(w, columns - x), minimumWidth),
      h: min(max(h, minimumHeight), maximumHeight))
  }

  /// The layout while panel `id` is dragged to `cell`, always from the layout
  /// the drag started on: the same cell gives the same layout, and coming
  /// back to the first cell gives the start back (`react-grid-layout` keeps
  /// `oldLayout` for the same reason).
  public static func dragPreview(startLayout: [PanelPlacement], id: ModuleID, cell: GridCell) -> [PanelPlacement] {
    move(startLayout, id: id, x: cell.x, y: cell.y)
  }

  /// The layout while panel `id` is resized to `size`, from the layout the
  /// resize started on.
  public static func resizePreview(startLayout: [PanelPlacement], id: ModuleID, size: GridSpan) -> [PanelPlacement] {
    resize(startLayout, id: id, w: size.w, h: size.h)
  }

  /// Moves panel `id` from the keyboard, `dx` columns or `dy` rows at a time.
  /// A row down that the compaction pulls straight back is no move, so the
  /// step grows until the panel lands somewhere else or runs out of grid.
  public static func nudge(_ layout: [PanelPlacement], id: ModuleID, dx: Int, dy: Int) -> [PanelPlacement] {
    guard dx != 0 || dy != 0, let placement = layout.first(where: { $0.i == id }) else { return layout }
    let steps = max(columns, bottom(layout) + 1)
    for step in 1...steps {
      let x = placement.x + dx * step
      let y = placement.y + dy * step
      guard x >= 0, x + placement.w <= columns, y >= 0 else { break }
      let moved = move(layout, id: id, x: x, y: y)
      if moved.first(where: { $0.i == id }) != placement { return moved }
    }
    return layout
  }

  /// Rounds a position in cells, keeping `previous` while it is near.
  static func snap(_ position: Double, previous: Int?) -> Int {
    guard position.isFinite else { return previous ?? 0 }
    if let previous, abs(position - Double(previous)) < cellSwitchDistance { return previous }
    // Bounded like `pixels`, so a degenerate width cannot trap on the conversion.
    return Int(min(max(jsRound(position), -1_000_000), 1_000_000))
  }

  /// The content height a layout needs (`containerHeight`).
  public static func contentHeight(_ layout: [PanelPlacement]) -> CGFloat {
    let rows = bottom(layout)
    guard rows > 0 else { return 0 }
    return CGFloat(rows) * rowHeight + CGFloat(rows - 1) * margin
  }

  // MARK: - react-grid-layout internals

  /// A placement plus the `moved` flag `moveElement` uses to avoid moving a
  /// panel twice in one pass.
  struct Node: Equatable {
    var i: ModuleID
    var x: Int
    var y: Int
    var w: Int
    var h: Int
    var moved = false

    init(_ placement: PanelPlacement) {
      i = placement.i
      x = placement.x
      y = placement.y
      w = placement.w
      h = placement.h
    }

    var placement: PanelPlacement { PanelPlacement(i: i, x: x, y: y, w: w, h: h) }
    var rect: Probe { Probe(x: x, y: y, w: w, h: h) }
  }

  /// A bare rectangle. As `moveElementAwayFromCollision`'s probe (id `-1`) it
  /// collides with every panel it overlaps, the moving one included.
  struct Probe {
    var x: Int
    var y: Int
    var w: Int
    var h: Int
  }

  static func collides(_ a: Node, _ b: Node) -> Bool {
    a.i != b.i && overlaps(a.rect, b.rect)
  }

  static func collides(_ a: Node, _ probe: Probe) -> Bool {
    overlaps(a.rect, probe)
  }

  static func overlaps(_ a: Probe, _ b: Probe) -> Bool {
    if a.x + a.w <= b.x { return false }
    if a.x >= b.x + b.w { return false }
    if a.y + a.h <= b.y { return false }
    if a.y >= b.y + b.h { return false }
    return true
  }

  /// `sortLayoutItemsByRowCol`; ties keep the input order, as JavaScript's stable sort does.
  static func sortedByRowColumn(_ nodes: [Node]) -> [Int] {
    nodes.indices.sorted { a, b in
      if nodes[a].y != nodes[b].y { return nodes[a].y < nodes[b].y }
      if nodes[a].x != nodes[b].x { return nodes[a].x < nodes[b].x }
      return a < b
    }
  }

  /// `verticalCompactor.compact`, without static items (the web has none).
  static func compact(_ layout: [Node]) -> [Node] {
    // `sorted` holds the items being compacted; `resolveCompactionCollision`
    // pushes the ones not yet reached, so later iterations see those pushes.
    let originalIndex = sortedByRowColumn(layout)
    var sorted = originalIndex.map { layout[$0] }
    var compareWith: [Node] = []
    var maxY = 0
    var output = layout
    for index in sorted.indices {
      var item = sorted[index]
      item.x = max(item.x, 0)
      item.y = max(item.y, 0)
      item.y = min(maxY, item.y)
      while item.y > 0 && !compareWith.contains(where: { collides($0, item) }) {
        item.y -= 1
      }
      while let collision = compareWith.first(where: { collides($0, item) }) {
        resolveCompactionCollision(&sorted, item: &item, at: index, moveTo: collision.y + collision.h)
      }
      item.y = max(item.y, 0)
      item.moved = false
      maxY = max(maxY, item.y + item.h)
      compareWith.append(item)
      sorted[index] = item
      output[originalIndex[index]] = item
    }
    return output
  }

  /// `resolveCompactionCollision` on the `y` axis: before `item` moves to
  /// `moveTo`, the items after it that it would then cover move down first.
  static func resolveCompactionCollision(_ sorted: inout [Node], item: inout Node, at index: Int, moveTo: Int) {
    item.y += 1
    var other = index + 1
    while other < sorted.count {
      if sorted[other].y > item.y + item.h { break }
      if collides(item, sorted[other]) {
        var pushed = sorted[other]
        resolveCompactionCollision(&sorted, item: &pushed, at: other, moveTo: moveTo + item.h)
        sorted[other] = pushed
      }
      other += 1
    }
    item.y = moveTo
  }

  /// `moveElement` with `compactType: "vertical"`, no collision prevention and
  /// no overlap. Items are found by id each time because the JavaScript works
  /// on shared references that every recursive call sees change.
  static func moveElement(_ layout: inout [Node], id: ModuleID, x: Int?, y: Int?, isUserAction: Bool) {
    guard let index = layout.firstIndex(where: { $0.i == id }) else { return }
    if layout[index].y == y && layout[index].x == x { return }
    let oldY = layout[index].y
    if let x { layout[index].x = x }
    if let y { layout[index].y = y }
    layout[index].moved = true

    var order = sortedByRowColumn(layout)
    let movingUp = y.map { oldY >= $0 } ?? false
    if movingUp { order.reverse() }
    let moving = layout[index]
    let collisions = order.filter { collides(layout[$0], moving) }.map { layout[$0].i }
    for collision in collisions {
      guard let current = layout.firstIndex(where: { $0.i == collision }), !layout[current].moved else { continue }
      moveAway(&layout, collidesWith: id, itemToMove: collision, isUserAction: isUserAction)
    }
  }

  /// `moveElementAwayFromCollision` for vertical compaction: when the user
  /// drags a panel onto another, the other first tries to hop above it; if it
  /// cannot, it steps down one row at a time until it no longer collides.
  static func moveAway(_ layout: inout [Node], collidesWith: ModuleID, itemToMove: ModuleID, isUserAction: Bool) {
    guard
      let still = layout.first(where: { $0.i == collidesWith }),
      let moving = layout.first(where: { $0.i == itemToMove })
    else { return }
    if isUserAction {
      let probe = Probe(x: moving.x, y: max(still.y - moving.h, 0), w: moving.w, h: moving.h)
      guard let first = layout.first(where: { collides($0, probe) }) else {
        moveElement(&layout, id: itemToMove, x: nil, y: probe.y, isUserAction: false)
        return
      }
      if first.y + first.h > still.y {
        moveElement(&layout, id: itemToMove, x: nil, y: moving.y + 1, isUserAction: false)
        return
      }
    }
    moveElement(&layout, id: itemToMove, x: nil, y: moving.y + 1, isUserAction: false)
  }

  /// `Math.round`: halves go up, also for negative numbers.
  static func jsRound(_ value: Double) -> Double {
    (value + 0.5).rounded(.down)
  }

  /// A window size as the server keeps it: rounded, and bounded so a doctored
  /// value cannot trap on the conversion.
  static func pixels(_ value: Double) -> Int {
    Int(min(max(jsRound(value), -1_000_000), 1_000_000))
  }
}
