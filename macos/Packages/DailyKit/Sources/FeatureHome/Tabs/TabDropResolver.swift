import CoreGraphics
import DailyModels

/// Where a dragged tab would land.
nonisolated enum TabDropTarget: Equatable, Sendable {
  /// Into a group's tab strip, before the tab at `index` (counted without the
  /// dragged tab, as `WorkspaceLayout.moving` expects).
  case strip(groupID: String, index: Int)
  /// On a group's edge: the group splits and the tab gets its own group there.
  case edge(groupID: String, edge: WorkspaceEdge)
  /// On the middle of a group: the tab joins it as its last tab.
  case group(groupID: String)

  /// Whether moving from `old` to `new` lands on a new target, which the view
  /// marks with an alignment haptic. Leaving every target is not a landing.
  static func isNewLanding(from old: TabDropTarget?, to new: TabDropTarget?) -> Bool {
    new != nil && new != old
  }
}

/// Turns the pointer of a tab drag into a drop target, the way Trellis does
/// (`@danfessler/trellis` `dist/index.js`, `tabTarget`, `dropEdge`, `filter`):
/// over a group's strip the tab goes between the tabs, split at their
/// midpoints; elsewhere within 28% of an edge it splits the group on that side;
/// in the middle it joins the group. Pure, so the view only feeds it frames.
nonisolated struct TabDropResolver: Equatable {
  nonisolated struct Tab: Equatable {
    var view: ModuleID
    /// Nil until the tab has been laid out and measured.
    var frame: CGRect?
  }

  nonisolated struct Zone: Equatable {
    var groupID: String
    var frame: CGRect
    var strip: CGRect
    /// In strip order.
    var tabs: [Tab]

    /// The index, among the tabs other than `view`, of the first tab whose
    /// midpoint is right of `x` (`tabTarget`).
    func insertionIndex(at x: CGFloat, dragging view: ModuleID) -> Int {
      let others = tabs.filter { $0.view != view }
      for (index, tab) in others.enumerated() {
        guard let frame = tab.frame else { continue }
        if x < frame.midX { return index }
      }
      return others.count
    }
  }

  /// `dropEdge`: how close to an edge, as a share of the group's size, splits it.
  static let edgeBand: CGFloat = 0.28
  /// The insertion bar drawn in a strip.
  static let insertionBarWidth: CGFloat = 2
  static let insertionBarInset: CGFloat = 6

  var zones: [Zone]

  init(zones: [Zone]) {
    self.zones = zones
  }

  /// Builds the zones from the laid-out groups, the tree and the measured tabs.
  init(geometry: WorkspaceGeometry, layout: WorkspaceLayout, tabFrames: [ModuleID: CGRect]) {
    zones = geometry.groups.compactMap { placed in
      guard let group = layout.group(id: placed.id) else { return nil }
      return Zone(
        groupID: placed.id,
        frame: placed.frame,
        strip: placed.strip,
        tabs: group.views.map { Tab(view: $0, frame: tabFrames[$0]) }
      )
    }
  }

  /// The target under `point` while dragging `view`, or nil when dropping there
  /// would change nothing or the point is outside every group.
  func target(at point: CGPoint, dragging view: ModuleID) -> TabDropTarget? {
    guard let zone = zones.first(where: { $0.frame.contains(point) }) else { return nil }
    let raw: TabDropTarget
    if zone.strip.contains(point) {
      raw = .strip(groupID: zone.groupID, index: zone.insertionIndex(at: point.x, dragging: view))
    } else if let edge = Self.edge(at: point, in: zone.frame) {
      raw = .edge(groupID: zone.groupID, edge: edge)
    } else {
      raw = .group(groupID: zone.groupID)
    }
    return filtered(raw, dragging: view)
  }

  /// Trellis' `filter`: a drop that would leave the layout as it is shows nothing.
  private func filtered(_ target: TabDropTarget, dragging view: ModuleID) -> TabDropTarget? {
    guard let source = zones.first(where: { zone in zone.tabs.contains { $0.view == view } }) else {
      return target
    }
    switch target {
    case .group(let groupID) where groupID == source.groupID:
      return nil
    case .edge(let groupID, _) where groupID == source.groupID && source.tabs.count == 1:
      return nil
    default:
      return target
    }
  }

  /// `dropEdge`: the nearest edge when it is within `edgeBand` of the size.
  static func edge(at point: CGPoint, in rect: CGRect) -> WorkspaceEdge? {
    guard rect.width > 0, rect.height > 0 else { return nil }
    let x = (point.x - rect.minX) / rect.width
    let y = (point.y - rect.minY) / rect.height
    guard (0...1).contains(x), (0...1).contains(y) else { return nil }
    let distances: [(edge: WorkspaceEdge, distance: CGFloat)] = [
      (edge: .left, distance: x),
      (edge: .right, distance: 1 - x),
      (edge: .top, distance: y),
      (edge: .bottom, distance: 1 - y),
    ]
    // The first of equal distances wins, as with Trellis' stable sort.
    var nearest = distances[0]
    for candidate in distances.dropFirst() where candidate.distance < nearest.distance {
      nearest = candidate
    }
    return nearest.distance <= edgeBand ? nearest.edge : nil
  }

  /// What the view draws for `target`, while dragging `view`: a bar between
  /// the tabs, the half of the group the new group would take (`dropRects`),
  /// or the whole group.
  func indicator(for target: TabDropTarget, dragging view: ModuleID) -> CGRect? {
    switch target {
    case .strip(let groupID, let index):
      guard let zone = findZone(withID: groupID) else { return nil }
      let others = zone.tabs.filter { $0.view != view }
      let x: CGFloat
      if index < others.count, let frame = others[index].frame {
        x = frame.minX - 1
      } else if let frame = others.last(where: { $0.frame != nil })?.frame {
        x = frame.maxX + 1
      } else {
        x = zone.strip.minX + Self.insertionBarInset
      }
      return CGRect(
        x: x - Self.insertionBarWidth / 2,
        y: zone.strip.minY + Self.insertionBarInset,
        width: Self.insertionBarWidth,
        height: max(0, zone.strip.height - Self.insertionBarInset * 2)
      )
    case .edge(let groupID, let edge):
      guard let zone = findZone(withID: groupID) else { return nil }
      return Self.slot(of: zone.frame, edge: edge)
    case .group(let groupID):
      return findZone(withID: groupID)?.frame
    }
  }

  /// `dropRects(...).slot`: the half of `rect` on `edge`.
  static func slot(of rect: CGRect, edge: WorkspaceEdge) -> CGRect {
    switch edge {
    case .left: CGRect(x: rect.minX, y: rect.minY, width: rect.width / 2, height: rect.height)
    case .right: CGRect(x: rect.midX, y: rect.minY, width: rect.width / 2, height: rect.height)
    case .top: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height / 2)
    case .bottom: CGRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2)
    }
  }

  private func findZone(withID groupID: String) -> Zone? {
    zones.first { $0.groupID == groupID }
  }

  /// The layout after dropping `view` on `target`, through the tree's own operations.
  static func apply(_ target: TabDropTarget, moving view: ModuleID, to layout: WorkspaceLayout) -> WorkspaceLayout {
    switch target {
    case .strip(let groupID, let index): layout.moving(view, to: groupID, at: index)
    case .group(let groupID): layout.moving(view, to: groupID)
    case .edge(let groupID, let edge): layout.splitting(groupID, with: view, edge: edge)
    }
  }
}
