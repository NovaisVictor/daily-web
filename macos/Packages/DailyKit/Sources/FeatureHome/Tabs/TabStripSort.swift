import CoreGraphics
import DailyModels

/// A tab dragged inside its own strip, as Trellis' `sortTabAtPointer`
/// (`@danfessler/trellis` `dist/index.js`): the dragged tab follows the pointer,
/// held within the strip, and its siblings slide to show where it would land.
/// The landing index is the drop resolver's own, so what the strip shows is
/// what the drop does. Pure: the view only draws the offsets.
nonisolated struct TabStripSort: Equatable {
  var groupID: String
  /// Where the tab would land, counted without it (as `TabDropTarget.strip`).
  var index: Int
  /// How far each tab is drawn from where the strip lays it out.
  var offsets: [ModuleID: CGFloat]

  func offset(of view: ModuleID) -> CGFloat {
    offsets[view] ?? 0
  }

  /// Nil while a tab of `zone` is not measured yet: without every width the
  /// siblings cannot be packed, and the drag falls back to the floating ghost.
  /// `start` is where the press began, so the tab keeps the grip it was taken by.
  init?(zone: TabDropResolver.Zone, dragging view: ModuleID, at point: CGPoint, from start: CGPoint, spacing: CGFloat) {
    var measured: [(view: ModuleID, frame: CGRect)] = []
    for tab in zone.tabs {
      guard let frame = tab.frame else { return nil }
      measured.append((view: tab.view, frame: frame))
    }
    guard let dragged = measured.first(where: { $0.view == view }), let first = measured.first else { return nil }

    let index = zone.insertionIndex(at: point.x, dragging: view)
    var order = measured.filter { $0.view != view }
    order.insert(dragged, at: min(index, order.count))

    let grip = start.x - dragged.frame.minX
    let lower = zone.strip.minX
    let upper = max(lower, zone.strip.maxX - dragged.frame.width)
    let followed = min(max(point.x - grip, lower), upper)

    var offsets: [ModuleID: CGFloat] = [:]
    var x = first.frame.minX
    for tab in order {
      offsets[tab.view] = (tab.view == view ? followed : x) - tab.frame.minX
      x += tab.frame.width + spacing
    }
    self.groupID = zone.groupID
    self.index = index
    self.offsets = offsets
  }
}

nonisolated extension TabDropResolver {
  /// The reordering shown while `view` is dragged over its own group's strip,
  /// or nil once the pointer leaves that strip (the tab then floats as a ghost).
  func sort(dragging view: ModuleID, at point: CGPoint, from start: CGPoint, spacing: CGFloat) -> TabStripSort? {
    guard
      let zone = zones.first(where: { zone in zone.tabs.contains { $0.view == view } }),
      zone.strip.contains(point)
    else { return nil }
    return TabStripSort(zone: zone, dragging: view, at: point, from: start, spacing: spacing)
  }
}
