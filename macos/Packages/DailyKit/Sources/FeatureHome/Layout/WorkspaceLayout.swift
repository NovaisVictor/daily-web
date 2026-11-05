import DailyModels
import Foundation

/// The home "Abas" arrangement: groups of tabs inside resizable splits, the
/// same tree as the web's Trellis document (`@danfessler/trellis` 0.3.0,
/// `LayoutDocument`), restricted to what the home page uses: no stage, no
/// floating or hidden panels, one view per module (`singleton`).
///
/// The web keeps it in the browser (`components/dashboard/WorkspaceHome.tsx`);
/// the Mac keeps it per account on disk (DP-3), so the two never sync.
public nonisolated struct WorkspaceLayout: Codable, Sendable, Equatable {
  /// Trellis' document schema.
  public static let schema = 1
  /// Bump when the default arrangement or the view ids change: a saved
  /// document with another version is discarded, as `LAYOUT_VERSION` does on the web.
  public static let currentVersion = 1
  /// No group is resized below this share of its split.
  public static let minimumShare = 0.1

  public var schema: Int
  public var version: Int
  public var root: WorkspaceNode?
  /// Next number for a generated node id. Kept in the document so ids never
  /// repeat after a relaunch.
  public var nextID: Int

  public init(root: WorkspaceNode?, nextID: Int, version: Int = WorkspaceLayout.currentVersion) {
    schema = Self.schema
    self.version = version
    self.root = root
    self.nextID = nextID
  }

  // MARK: - Default

  /// `defaultLayoutFor` (`WorkspaceHome.tsx:43-49`): one row with two columns
  /// sized 3:2, the left one holding the first half of the modules (rounded
  /// up), each module in its own group, in the web's panel order.
  public static func makeDefault(modules: [ModuleID]) -> WorkspaceLayout {
    let ordered = ModuleID.known.filter(modules.contains)
    var layout = WorkspaceLayout(root: nil, nextID: 1)
    guard !ordered.isEmpty else { return layout }
    let groups = ordered.map { layout.makeGroup(views: [$0]) }
    if groups.count == 1 {
      layout.root = .group(groups[0])
      return layout
    }
    let half = (groups.count + 1) / 2
    let left = layout.makeSplit(axis: .y, children: groups[..<half].map(WorkspaceNode.group))
    let right = layout.makeSplit(axis: .y, children: groups[half...].map(WorkspaceNode.group))
    layout.root = .split(
      layout.makeSplit(axis: .x, children: [left, right].map(WorkspaceNode.split), weights: [3, 2]))
    layout.normalize()
    return layout
  }

  // MARK: - Persistence

  /// Reads a saved document. Nil when it was saved with another schema or
  /// version (it is then discarded, like Trellis does); throws when the data is
  /// not a document at all.
  public static func decode(_ data: Data) throws -> WorkspaceLayout? {
    let header = try JSONDecoder().decode(Header.self, from: data)
    guard header.schema == schema, header.version == currentVersion else { return nil }
    var layout = try JSONDecoder().decode(WorkspaceLayout.self, from: data)
    layout.normalize()
    return layout
  }

  public func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(self)
  }

  private struct Header: Decodable {
    var schema: Int
    var version: Int?
  }

  // MARK: - Reading

  /// Every group, left to right and top to bottom.
  public var groups: [WorkspaceGroup] { root?.groups ?? [] }

  /// Every module shown, in group order.
  public var views: [ModuleID] { groups.flatMap(\.views) }

  public func group(id: String) -> WorkspaceGroup? {
    groups.first { $0.id == id }
  }

  public func group(containing view: ModuleID) -> WorkspaceGroup? {
    groups.first { $0.views.contains(view) }
  }

  public func split(id: String) -> WorkspaceSplit? {
    root?.findSplit(id: id)
  }

  // MARK: - Editing

  /// Makes `view` the active tab of its group.
  public func selecting(_ view: ModuleID) -> WorkspaceLayout {
    guard var group = group(containing: view), group.selected != view else { return self }
    group.selected = view
    var next = self
    next.root = root?.replacingGroup(group)
    return next
  }

  /// Moves the tab `view` into group `groupID` at `index` (the end when nil),
  /// where it becomes the active tab. Within the same group this reorders. A
  /// group left empty disappears and its split collapses.
  public func moving(_ view: ModuleID, to groupID: String, at index: Int? = nil) -> WorkspaceLayout {
    guard let source = group(containing: view), let target = group(id: groupID) else { return self }
    var next = self
    if source.id == target.id {
      var group = source
      group.views.removeAll { $0 == view }
      group.views.insert(view, at: min(max(index ?? group.views.count, 0), group.views.count))
      group.selected = view
      next.root = root?.replacingGroup(group)
      return next
    }
    next.detach(view)
    guard var destination = next.group(id: groupID) else { return self }
    destination.views.insert(view, at: min(max(index ?? destination.views.count, 0), destination.views.count))
    destination.selected = view
    next.root = next.root?.replacingGroup(destination)
    next.normalize()
    return next
  }

  /// Drops the tab `view` on an edge of group `groupID`: the group splits and
  /// the tab gets a group of its own on that side, taking `share` of the space
  /// (`insertBeside`, clamped to 0.1–0.9). Dropping a group's only tab on its
  /// own edge changes nothing.
  public func splitting(_ groupID: String, with view: ModuleID, edge: WorkspaceEdge, share: Double = 0.5)
    -> WorkspaceLayout
  {
    guard let source = group(containing: view), group(id: groupID) != nil else { return self }
    if source.id == groupID && source.views.count == 1 { return self }
    var next = self
    next.detach(view)
    guard next.group(id: groupID) != nil, let root = next.root else { return self }
    let incoming = WorkspaceNode.group(next.makeGroup(views: [view]))
    let clamped = min(0.9, max(0.1, share.isFinite ? share : 0.5))
    let splitID = next.makeID("split")
    next.root = root.inserting(incoming, beside: groupID, edge: edge, share: clamped, splitID: splitID)
    next.normalize()
    return next
  }

  /// Moves the boundary after child `boundary` of split `splitID` by `delta`
  /// (a fraction of the split). The two neighbours trade space, the total
  /// stays the same, and neither goes below `minimumShare`.
  public func resizing(split splitID: String, boundary: Int, by delta: Double) -> WorkspaceLayout {
    guard
      delta.isFinite,
      var split = split(id: splitID),
      boundary >= 0, boundary + 1 < split.weights.count
    else { return self }
    let pair = split.weights[boundary] + split.weights[boundary + 1]
    let total = split.weights.reduce(0, +)
    let floor = min(Self.minimumShare * total, pair / 2)
    let first = min(max(split.weights[boundary] + delta * total, floor), pair - floor)
    split.weights[boundary] = first
    split.weights[boundary + 1] = pair - first
    var next = self
    next.root = root?.replacingSplit(split)
    return next
  }

  /// Follows the enabled modules (`WorkspaceHome.tsx:81-96`): a module turned
  /// off disappears, one turned on opens as a tab of the last group. Unknown
  /// modules have no panel and are left out; a module shown twice keeps its
  /// first tab.
  public func reconciled(with modules: [ModuleID]) -> WorkspaceLayout {
    let enabled = ModuleID.known.filter(modules.contains)
    var next = self
    var seen: Set<ModuleID> = []
    next.root = root?.filteringViews { view in
      guard enabled.contains(view), !seen.contains(view) else { return false }
      seen.insert(view)
      return true
    }
    next.normalize()
    let missing = enabled.filter { !seen.contains($0) }
    guard !missing.isEmpty else { return next }
    guard var last = next.groups.last else {
      return Self.makeDefault(modules: enabled)
    }
    last.views.append(contentsOf: missing)
    next.root = next.root?.replacingGroup(last)
    return next
  }

  // MARK: - Tree upkeep

  /// Trellis' `normalize`: empty groups go, a split with one child becomes that
  /// child, a split inside one of the same axis merges into it, and weights
  /// sum to 1 (a missing or invalid weight counts as 0.001). A group's active
  /// tab is always one of its tabs.
  mutating func normalize() {
    root = root?.normalized()
  }

  /// Takes `view` out of its group, selecting its neighbour if it was active
  /// (`detachView`); the group disappears when it was the last tab.
  mutating func detach(_ view: ModuleID) {
    guard var group = group(containing: view) else { return }
    let index = group.views.firstIndex(of: view) ?? 0
    group.views.removeAll { $0 == view }
    if group.selected == view, !group.views.isEmpty {
      group.selected = group.views[min(index, group.views.count - 1)]
    }
    root = root?.replacingGroup(group)
    normalize()
  }

  mutating func makeID(_ prefix: String) -> String {
    defer { nextID += 1 }
    return "\(prefix)-\(nextID)"
  }

  mutating func makeGroup(views: [ModuleID]) -> WorkspaceGroup {
    WorkspaceGroup(id: makeID("panel"), views: views, selected: views[0])
  }

  mutating func makeSplit(axis: WorkspaceAxis, children: [WorkspaceNode], weights: [Double]? = nil)
    -> WorkspaceSplit
  {
    WorkspaceSplit(
      id: makeID("split"), axis: axis, weights: weights ?? children.map { _ in 1 }, children: children)
  }
}

/// `x` lays children side by side (a row), `y` stacks them (a column).
public nonisolated enum WorkspaceAxis: String, Codable, Sendable, Equatable {
  case x
  case y
}

/// The side of a group a tab is dropped on.
public nonisolated enum WorkspaceEdge: String, Codable, Sendable, Equatable, CaseIterable {
  case left
  case right
  case top
  case bottom

  var axis: WorkspaceAxis { self == .left || self == .right ? .x : .y }
  /// The new group goes before the target.
  var isBefore: Bool { self == .left || self == .top }
}

/// A tab group (Trellis' `PanelNode`).
public nonisolated struct WorkspaceGroup: Codable, Sendable, Equatable, Identifiable {
  public var id: String
  public var views: [ModuleID]
  public var selected: ModuleID

  public init(id: String, views: [ModuleID], selected: ModuleID) {
    self.id = id
    self.views = views
    self.selected = selected
  }
}

/// A weighted row or column (Trellis' `SplitNode`).
public nonisolated struct WorkspaceSplit: Codable, Sendable, Equatable, Identifiable {
  public var id: String
  public var axis: WorkspaceAxis
  /// Relative sizes, normalized to sum to 1.
  public var weights: [Double]
  public var children: [WorkspaceNode]

  public init(id: String, axis: WorkspaceAxis, weights: [Double], children: [WorkspaceNode]) {
    self.id = id
    self.axis = axis
    self.weights = weights
    self.children = children
  }
}

/// A node of the tree, encoded with Trellis' `kind` tag (`split` or `panel`).
public nonisolated indirect enum WorkspaceNode: Codable, Sendable, Equatable, Identifiable {
  case split(WorkspaceSplit)
  case group(WorkspaceGroup)

  public var id: String {
    switch self {
    case .split(let split): split.id
    case .group(let group): group.id
    }
  }

  private enum CodingKeys: String, CodingKey {
    case kind
  }

  private enum Kind: String, Codable {
    case split
    case panel
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(Kind.self, forKey: .kind) {
    case .split: self = .split(try WorkspaceSplit(from: decoder))
    case .panel: self = .group(try WorkspaceGroup(from: decoder))
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .split(let split):
      try container.encode(Kind.split, forKey: .kind)
      try split.encode(to: encoder)
    case .group(let group):
      try container.encode(Kind.panel, forKey: .kind)
      try group.encode(to: encoder)
    }
  }

  var groups: [WorkspaceGroup] {
    switch self {
    case .group(let group): [group]
    case .split(let split): split.children.flatMap(\.groups)
    }
  }

  func findSplit(id: String) -> WorkspaceSplit? {
    guard case .split(let split) = self else { return nil }
    if split.id == id { return split }
    return split.children.lazy.compactMap { $0.findSplit(id: id) }.first
  }

  func replacingGroup(_ replacement: WorkspaceGroup) -> WorkspaceNode {
    switch self {
    case .group(let group): return group.id == replacement.id ? .group(replacement) : self
    case .split(var split):
      split.children = split.children.map { $0.replacingGroup(replacement) }
      return .split(split)
    }
  }

  func replacingSplit(_ replacement: WorkspaceSplit) -> WorkspaceNode {
    guard case .split(var split) = self else { return self }
    if split.id == replacement.id { return .split(replacement) }
    split.children = split.children.map { $0.replacingSplit(replacement) }
    return .split(split)
  }

  func filteringViews(_ keep: (ModuleID) -> Bool) -> WorkspaceNode {
    switch self {
    case .group(var group):
      let index = group.views.firstIndex(of: group.selected) ?? 0
      group.views = group.views.filter(keep)
      if !group.views.contains(group.selected), !group.views.isEmpty {
        group.selected = group.views[min(index, group.views.count - 1)]
      }
      return .group(group)
    case .split(var split):
      split.children = split.children.map { $0.filteringViews(keep) }
      return .split(split)
    }
  }

  /// `insertBeside`: wraps the target in a split along the edge's axis.
  func inserting(
    _ incoming: WorkspaceNode, beside targetID: String, edge: WorkspaceEdge, share: Double, splitID: String
  ) -> WorkspaceNode {
    if id == targetID {
      let wrapper = WorkspaceSplit(
        id: splitID,
        axis: edge.axis,
        weights: edge.isBefore ? [share, 1 - share] : [1 - share, share],
        children: edge.isBefore ? [incoming, self] : [self, incoming]
      )
      return .split(wrapper)
    }
    guard case .split(var split) = self else { return self }
    split.children = split.children.map {
      $0.inserting(incoming, beside: targetID, edge: edge, share: share, splitID: splitID)
    }
    return .split(split)
  }

  /// Trellis' `normalize` (`src/model/tree.ts`); nil when nothing is left.
  func normalized() -> WorkspaceNode? {
    switch self {
    case .group(var group):
      guard !group.views.isEmpty else { return nil }
      if !group.views.contains(group.selected) { group.selected = group.views[0] }
      return .group(group)
    case .split(var split):
      var children: [WorkspaceNode] = []
      var weights: [Double] = []
      for (index, child) in split.children.enumerated() {
        let raw = index < split.weights.count ? split.weights[index] : 1
        let weight = raw.isFinite && raw > 0 ? raw : 1e-3
        guard let next = child.normalized() else { continue }
        if case .split(let inner) = next, inner.axis == split.axis {
          let total = inner.weights.reduce(0, +)
          for (grandchild, share) in zip(inner.children, inner.weights) {
            children.append(grandchild)
            weights.append(weight * share / total)
          }
        } else {
          children.append(next)
          weights.append(weight)
        }
      }
      guard !children.isEmpty else { return nil }
      if children.count == 1 { return children[0] }
      let total = weights.reduce(0, +)
      split.children = children
      split.weights = weights.map { $0 / total }
      return .split(split)
    }
  }
}
