import Foundation

/// While a batch is dragged, the selected rows gather toward the dragged one:
/// what leaves the list is a "maço", not a row (`deslocamentoDoMaco`,
/// `EmailPanel.tsx:127-138`). The farther a row is, the deeper it sits in the
/// pile, with a cap so a long selection does not cross the whole screen.
nonisolated enum EmailDragStack {
  struct Placement: Equatable, Sendable {
    /// Points toward the dragged row: positive moves down.
    var offsetY: CGFloat
    var scale: CGFloat
    var zIndex: Double
  }

  /// The furthest a row travels (`28px`).
  static let maxOffset: CGFloat = 28

  /// Where the row at `index` of the screen order goes while the row at
  /// `dragged` is being dragged; nil when nothing is.
  static func placement(index: Int, dragged: Int?) -> Placement? {
    guard let dragged else { return nil }
    let distance = dragged - index
    let offset: CGFloat = max(min(CGFloat(distance) * 10, maxOffset), -maxOffset)
    let depth = min(abs(distance), 3)
    let scale: CGFloat = 1 - CGFloat(depth) * 0.012
    return Placement(offsetY: offset, scale: scale, zIndex: Double(10 - depth))
  }
}
