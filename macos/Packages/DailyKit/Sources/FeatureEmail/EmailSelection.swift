/// The list selection, like a file manager's (`lib/emailSelection.ts`): a click
/// replaces, ⌘-click adds or removes, ⇧ marks the range, and the arrows walk the
/// list with ⇧ extending. Pure, so the rules can be exercised without a screen.
nonisolated struct EmailSelection: Equatable, Sendable {
  /// In list order, without repeats.
  var selected: [String]
  /// Where a range starts: the last click without ⇧.
  var anchor: String?
  /// Where the keyboard is.
  var cursor: String?

  static let empty = EmailSelection(selected: [], anchor: nil, cursor: nil)

  enum Event: Equatable, Sendable {
    case click(String, shift: Bool = false, meta: Bool = false)
    case toggle(String)
    case move(down: Bool, extend: Bool = false)
    case all
    /// A group header checkbox: a fully marked group unmarks, anything else marks it.
    case group([String])
    /// Right click: inside the selection it stays; outside, the row becomes the selection.
    case context(String)
    case clear
    /// The list changed: what is gone leaves the selection.
    case sync
  }

  func reduced(_ event: Event, order: [String]) -> EmailSelection {
    switch event {
    case .click(let id, let shift, let meta):
      // Without an anchor, ⇧ has nowhere to start from and the click stands alone.
      if shift, let anchor {
        let range = Self.range(order, from: anchor, to: id)
        let base = meta ? selected + range : range
        return EmailSelection(selected: Self.inOrder(base, order), anchor: anchor, cursor: id)
      }
      if meta { return toggled(id, order: order) }
      return EmailSelection(selected: [id], anchor: id, cursor: id)

    case .toggle(let id):
      return toggled(id, order: order)

    case .move(let down, let extend):
      guard !order.isEmpty else { return self }
      let current = cursor.flatMap { order.firstIndex(of: $0) }
      // At the ends the cursor stops instead of wrapping around.
      let target: Int
      if let current {
        target = min(max(current + (down ? 1 : -1), 0), order.count - 1)
      } else {
        target = down ? 0 : order.count - 1
      }
      let id = order[target]
      if extend, let anchor {
        return EmailSelection(selected: Self.range(order, from: anchor, to: id), anchor: anchor, cursor: id)
      }
      return EmailSelection(selected: [id], anchor: id, cursor: id)

    case .all:
      return EmailSelection(selected: order, anchor: order.first, cursor: order.last)

    case .group(let ids):
      let inList = Set(order)
      let ofGroup = ids.filter { inList.contains($0) }
      guard let first = ofGroup.first else { return self }
      var current = Set(selected)
      let whole = ofGroup.allSatisfy { current.contains($0) }
      for id in ofGroup {
        if whole { current.remove(id) } else { current.insert(id) }
      }
      return EmailSelection(selected: Self.inOrder(current, order), anchor: first, cursor: first)

    case .context(let id):
      if selected.contains(id) { return self }
      return EmailSelection(selected: [id], anchor: id, cursor: id)

    case .clear:
      return .empty

    case .sync:
      let inList = Set(order)
      return EmailSelection(
        selected: Self.inOrder(selected, order),
        anchor: anchor.flatMap { inList.contains($0) ? $0 : nil },
        cursor: cursor.flatMap { inList.contains($0) ? $0 : nil }
      )
    }
  }

  private func toggled(_ id: String, order: [String]) -> EmailSelection {
    var current = Set(selected)
    if current.contains(id) { current.remove(id) } else { current.insert(id) }
    return EmailSelection(selected: Self.inOrder(current, order), anchor: id, cursor: id)
  }

  /// List order: a click order would hand a shuffled batch to whoever applies it.
  private static func inOrder<S: Sequence<String>>(_ ids: S, _ order: [String]) -> [String] {
    let set = Set(ids)
    return order.filter { set.contains($0) }
  }

  private static func range(_ order: [String], from: String, to: String) -> [String] {
    guard let i = order.firstIndex(of: from), let j = order.firstIndex(of: to) else { return [] }
    return Array(order[min(i, j)...max(i, j)])
  }
}
