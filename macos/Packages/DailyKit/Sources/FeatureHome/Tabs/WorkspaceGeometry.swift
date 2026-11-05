import CoreGraphics
import DailyModels

/// Where each group and divider of a `WorkspaceLayout` sits in a canvas of a
/// given size. Trellis positions its panels absolutely from the same tree
/// (`@danfessler/trellis`, `--trellis-gap`, `--trellis-tabbar-height`); doing
/// the math here keeps the view a plain placement and the drop hit-testing pure.
nonisolated struct WorkspaceGeometry: Equatable {
  nonisolated struct Metrics: Equatable {
    /// `--trellis-gap`: the space between groups, where the dividers sit.
    var gap: CGFloat = 6
    /// `--trellis-tabbar-height`.
    var stripHeight: CGFloat = 34
    /// No group is resized below these, on top of `WorkspaceLayout.minimumShare`.
    var minimumGroupSize = CGSize(width: 200, height: 140)
    /// A divider is easier to grab than the gap it sits in (`MIN_SEAM_HIT_WIDTH`).
    var dividerHitThickness: CGFloat = 8

    static let standard = Metrics()
  }

  nonisolated struct Group: Equatable, Identifiable {
    var id: String
    /// The whole group: tab strip and panel.
    var frame: CGRect
    var strip: CGRect
    /// Below the strip, where the selected tab's panel goes.
    var content: CGRect
  }

  /// The boundary after child `boundary` of split `splitID`.
  nonisolated struct Divider: Equatable, Identifiable {
    var splitID: String
    var boundary: Int
    var axis: WorkspaceAxis
    /// The area that grabs the pointer, centred on the gap.
    var frame: CGRect
    /// The split's length along its axis, gaps excluded: what the weights share.
    var length: CGFloat
    /// The smallest the children on each side can get along the axis.
    var minimumBefore: CGFloat
    var minimumAfter: CGFloat

    var id: String { "\(splitID):\(boundary)" }
  }

  let metrics: Metrics
  private(set) var groups: [Group] = []
  private(set) var dividers: [Divider] = []

  init(root: WorkspaceNode?, size: CGSize, metrics: Metrics = .standard) {
    self.metrics = metrics
    guard let root else { return }
    place(root, in: CGRect(origin: .zero, size: size))
  }

  func group(id: String) -> Group? {
    groups.first { $0.id == id }
  }

  private mutating func place(_ node: WorkspaceNode, in rect: CGRect) {
    switch node {
    case .group(let group):
      let stripHeight = min(metrics.stripHeight, rect.height)
      let strip = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: stripHeight)
      let content = CGRect(
        x: rect.minX, y: rect.minY + stripHeight, width: rect.width, height: rect.height - stripHeight)
      groups.append(Group(id: group.id, frame: rect, strip: strip, content: content))
    case .split(let split):
      placeSplit(split, in: rect)
    }
  }

  private mutating func placeSplit(_ split: WorkspaceSplit, in rect: CGRect) {
    let count = split.children.count
    guard count > 0 else { return }
    let isRow = split.axis == .x
    let extent = isRow ? rect.width : rect.height
    let length = max(0, extent - metrics.gap * CGFloat(count - 1))
    let total = split.weights.reduce(0, +)
    var cursor = isRow ? rect.minX : rect.minY
    for (index, child) in split.children.enumerated() {
      let weight = index < split.weights.count ? split.weights[index] : 0
      let size = total > 0 ? length * CGFloat(weight / total) : length / CGFloat(count)
      let childRect =
        isRow
        ? CGRect(x: cursor, y: rect.minY, width: size, height: rect.height)
        : CGRect(x: rect.minX, y: cursor, width: rect.width, height: size)
      place(child, in: childRect)
      cursor += size
      guard index + 1 < count else { continue }
      let thickness = max(metrics.gap, metrics.dividerHitThickness)
      let centre = cursor + metrics.gap / 2
      let frame =
        isRow
        ? CGRect(x: centre - thickness / 2, y: rect.minY, width: thickness, height: rect.height)
        : CGRect(x: rect.minX, y: centre - thickness / 2, width: rect.width, height: thickness)
      dividers.append(
        Divider(
          splitID: split.id,
          boundary: index,
          axis: split.axis,
          frame: frame,
          length: length,
          minimumBefore: minimumLength(of: child, along: split.axis),
          minimumAfter: minimumLength(of: split.children[index + 1], along: split.axis)
        ))
      cursor += metrics.gap
    }
  }

  /// The smallest `node` can be along `axis` with every group at its minimum.
  func minimumLength(of node: WorkspaceNode, along axis: WorkspaceAxis) -> CGFloat {
    switch node {
    case .group:
      return axis == .x ? metrics.minimumGroupSize.width : metrics.minimumGroupSize.height
    case .split(let split):
      let lengths = split.children.map { minimumLength(of: $0, along: axis) }
      guard split.axis == axis else { return lengths.max() ?? 0 }
      return lengths.reduce(0, +) + metrics.gap * CGFloat(max(0, lengths.count - 1))
    }
  }

  /// The share (a fraction of the split, as `WorkspaceLayout.resizing` takes)
  /// that moving `divider` by `translation` points gives, clamped so neither
  /// side goes below its minimum. A side already below it (a small window) is
  /// not shrunk further, but is not forced to grow either.
  static func resizeDelta(translation: CGFloat, divider: Divider, weights: [Double]) -> Double {
    let boundary = divider.boundary
    guard divider.length > 0, translation.isFinite, boundary >= 0, boundary + 1 < weights.count else { return 0 }
    let total = weights.reduce(0, +)
    guard total > 0 else { return 0 }
    let before = weights[boundary] / total
    let after = weights[boundary + 1] / total
    let pair = before + after
    let length = Double(divider.length)
    let minimumBefore = min(Double(divider.minimumBefore) / length, pair / 2)
    let minimumAfter = min(Double(divider.minimumAfter) / length, pair / 2)
    let lower = min(minimumBefore - before, 0)
    let upper = max(after - minimumAfter, 0)
    return min(max(Double(translation) / length, lower), upper)
  }

  /// The share that makes both sides of `divider` equal (double-click, as Trellis' `equalize`).
  static func equalizingDelta(divider: Divider, weights: [Double]) -> Double {
    let boundary = divider.boundary
    guard boundary >= 0, boundary + 1 < weights.count else { return 0 }
    let total = weights.reduce(0, +)
    guard total > 0 else { return 0 }
    return ((weights[boundary] + weights[boundary + 1]) / 2 - weights[boundary]) / total
  }
}
