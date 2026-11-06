import CoreGraphics
import DailyModels
import Observation

/// A move or resize of one panel, from the press that started it to its end
/// (`react-grid-layout`'s `oldLayout`, `oldDragItem` and placeholder). Every
/// preview is computed from `startLayout`, so the layout under the pointer
/// depends only on where the pointer is, never on the path it took.
nonisolated struct GridDragSession: Equatable, Sendable {
  enum Kind: Equatable, Sendable {
    case move
    case resize
  }

  /// The cell a move points at, or the size a resize asks for.
  enum Target: Equatable, Sendable {
    case cell(GridCell)
    case span(GridSpan)
  }

  let module: ModuleID
  let kind: Kind
  /// Where the press began, in the grid's coordinate space. It tells one
  /// pointer gesture from the next even when an end was never heard.
  let startLocation: CGPoint
  let startLayout: [PanelPlacement]
  let startPlacement: PanelPlacement
  /// Where the panel was drawn when the gesture began.
  let startFrame: CGRect
  /// The grid's height when the gesture began. The grid never gets shorter
  /// while it lasts, so the scroll view does not move under a still pointer.
  let startContentHeight: CGFloat
  private(set) var target: Target
  /// What the grid draws while the gesture lasts; the placeholder sits on the
  /// panel's place in it.
  private(set) var preview: [PanelPlacement]

  init?(module: ModuleID, kind: Kind, startLocation: CGPoint, layout: [PanelPlacement], containerWidth: CGFloat) {
    guard let placement = layout.first(where: { $0.i == module }) else { return nil }
    self.module = module
    self.kind = kind
    self.startLocation = startLocation
    startLayout = layout
    startPlacement = placement
    startFrame = DashboardLayoutEngine.frame(for: placement, containerWidth: containerWidth)
    startContentHeight = DashboardLayoutEngine.contentHeight(layout)
    switch kind {
    case .move: target = .cell(GridCell(x: placement.x, y: placement.y))
    case .resize: target = .span(GridSpan(w: placement.w, h: placement.h))
    }
    preview = layout
  }

  func belongs(module: ModuleID, kind: Kind, startLocation: CGPoint) -> Bool {
    self.module == module && self.kind == kind && self.startLocation == startLocation
  }

  /// Points the gesture at where `translation` carries the panel. True when
  /// the target changed, and with it the preview.
  mutating func follow(_ translation: CGSize, containerWidth: CGFloat) -> Bool {
    let next: Target
    switch target {
    case .cell(let previous):
      let origin = CGPoint(x: startFrame.minX + translation.width, y: startFrame.minY + translation.height)
      next = .cell(
        DashboardLayoutEngine.cell(
          for: origin, w: startPlacement.w, containerWidth: containerWidth, previous: previous))
    case .span(let previous):
      let size = CGSize(
        width: max(0, startFrame.width + translation.width), height: max(0, startFrame.height + translation.height))
      next = .span(
        DashboardLayoutEngine.span(
          for: size, x: startPlacement.x, containerWidth: containerWidth, previous: previous))
    }
    guard next != target else { return false }
    target = next
    switch next {
    case .cell(let cell):
      preview = DashboardLayoutEngine.dragPreview(startLayout: startLayout, id: module, cell: cell)
    case .span(let span):
      preview = DashboardLayoutEngine.resizePreview(startLayout: startLayout, id: module, size: span)
    }
    return true
  }
}

/// The gesture in progress, apart from any view: SwiftUI drops a drag's
/// `onEnded` when the view holding the gesture goes away, so the state has
/// to live where the end of the arrange mode can clear it.
nonisolated struct GridGestureTracker: Equatable, Sendable {
  enum Outcome: Equatable, Sendable {
    /// Not a gesture the grid follows: cancelled, or on a panel it does not draw.
    case ignored
    /// The pointer moved within the same target.
    case followed
    /// The target changed, and so did the preview.
    case changed
  }

  private(set) var session: GridDragSession?
  /// The press of a gesture cancelled with Esc. The pointer is still down, so
  /// its next events must not start the gesture again.
  private var cancelledStart: CGPoint?

  mutating func update(
    module: ModuleID, kind: GridDragSession.Kind, startLocation: CGPoint, translation: CGSize,
    layout: [PanelPlacement], containerWidth: CGFloat
  ) -> Outcome {
    if cancelledStart == startLocation { return .ignored }
    cancelledStart = nil
    if session?.belongs(module: module, kind: kind, startLocation: startLocation) != true {
      session = GridDragSession(
        module: module, kind: kind, startLocation: startLocation, layout: layout, containerWidth: containerWidth)
    }
    guard var current = session else { return .ignored }
    let changed = current.follow(translation, containerWidth: containerWidth)
    session = current
    return changed ? .changed : .followed
  }

  /// The pointer was released: the layout the gesture leaves, or nil when it
  /// left the start as it was.
  mutating func end() -> [PanelPlacement]? {
    defer {
      session = nil
      cancelledStart = nil
    }
    guard let session, session.preview != session.startLayout else { return nil }
    return session.preview
  }

  /// Esc during a gesture: the panel goes back to where the gesture found it.
  /// False when there was no gesture to cancel.
  mutating func cancel() -> Bool {
    guard let session else { return false }
    cancelledStart = session.startLocation
    self.session = nil
    return true
  }

  /// The arrange mode ended: nothing of the gesture survives it.
  mutating func reset() {
    session = nil
    cancelledStart = nil
  }
}

/// How far the pointer carried the panel under a gesture. Kept apart from
/// the arrangement so only the panel that follows it redraws on every event.
@Observable
final class GridPointer {
  private(set) var translation: CGSize = .zero

  func update(_ translation: CGSize) {
    guard translation != self.translation else { return }
    self.translation = translation
  }
}
