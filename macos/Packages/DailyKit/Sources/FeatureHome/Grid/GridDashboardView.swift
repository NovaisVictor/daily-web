import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// The wide Início grid (`components/DashboardGrid.tsx`): 12 columns, rows of
/// 32 pt and gaps of 24 pt, each panel on the glass panel surface. Holding a
/// panel for 0.5 s starts the arrange mode, where dragging moves a panel and
/// the bottom-right handle resizes it.
struct GridDashboardView: View {
  static let coordinateSpace = "GridDashboard"
  /// Room under the last panel while arranging (`pb-28`), so the floating bar
  /// never covers a resize handle.
  static let arrangingBottomPadding: CGFloat = 112

  let window: HomeWindowState
  let panel: (ModuleID) -> AnyView

  @State private var containerWidth: CGFloat = 0
  /// The move or resize in progress.
  @State private var gesture: GridGesture?

  var body: some View {
    let layout = window.gridLayout
    let arranging = window.grid.isArranging
    GridDashboardLayout {
      if let gesture, gesture.kind == .move, let target = layout.first(where: { $0.i == gesture.module }) {
        GridPlaceholder()
          .layoutValue(key: GridPlacementKey.self, value: target)
      }
      ForEach(Array(layout.enumerated()), id: \.element.i) { index, placement in
        GridPanelCell(
          module: placement.i,
          content: panel(placement.i),
          index: index,
          arranging: arranging,
          isActive: window.grid.activePanel == placement.i,
          offset: offset(of: placement),
          begin: { window.beginArranging() },
          move: { value in move(placement, value) },
          resize: { value in resize(placement, value) },
          end: endGesture
        )
        .layoutValue(key: GridPlacementKey.self, value: placement)
        .zIndex(gesture?.module == placement.i ? 1 : 0)
      }
    }
    .coordinateSpace(.named(Self.coordinateSpace))
    .onGeometryChange(for: CGFloat.self) { proxy in
      proxy.size.width
    } action: { width in
      containerWidth = width
    }
    .padding(.bottom, arranging ? Self.arrangingBottomPadding : 0)
  }

  /// A moved panel follows the pointer; the grid only places its cell.
  private func offset(of placement: PanelPlacement) -> CGSize {
    guard let gesture, gesture.kind == .move, gesture.module == placement.i else { return .zero }
    let current = DashboardLayoutEngine.frame(for: placement, containerWidth: containerWidth)
    return CGSize(
      width: gesture.startFrame.minX + gesture.translation.width - current.minX,
      height: gesture.startFrame.minY + gesture.translation.height - current.minY)
  }

  private func start(_ kind: GridGesture.Kind, _ placement: PanelPlacement) -> GridGesture {
    if let gesture, gesture.module == placement.i, gesture.kind == kind { return gesture }
    window.grid.setActive(placement.i)
    let frame = DashboardLayoutEngine.frame(for: placement, containerWidth: containerWidth)
    return GridGesture(module: placement.i, kind: kind, startFrame: frame, translation: .zero)
  }

  private func move(_ placement: PanelPlacement, _ value: DragGesture.Value) {
    var next = start(.move, placement)
    next.translation = value.translation
    gesture = next
    let origin = CGPoint(
      x: next.startFrame.minX + value.translation.width, y: next.startFrame.minY + value.translation.height)
    let cell = DashboardLayoutEngine.gridPosition(
      origin: origin, w: placement.w, h: placement.h, containerWidth: containerWidth)
    window.movePanel(placement.i, x: cell.x, y: cell.y)
  }

  private func resize(_ placement: PanelPlacement, _ value: DragGesture.Value) {
    var next = start(.resize, placement)
    next.translation = value.translation
    gesture = next
    let size = CGSize(
      width: max(0, next.startFrame.width + value.translation.width),
      height: max(0, next.startFrame.height + value.translation.height))
    let cells = DashboardLayoutEngine.gridSize(size: size, x: placement.x, containerWidth: containerWidth)
    window.resizePanel(placement.i, w: cells.w, h: cells.h)
  }

  private func endGesture() {
    gesture = nil
    window.grid.setActive(nil)
  }
}

/// A move or resize in progress, in the grid's coordinate space.
struct GridGesture: Equatable {
  enum Kind: Equatable {
    case move
    case resize
  }

  var module: ModuleID
  var kind: Kind
  /// Where the panel was drawn when the gesture began.
  var startFrame: CGRect
  var translation: CGSize
}

/// Each grid child's place, in grid units.
nonisolated struct GridPlacementKey: LayoutValueKey {
  static let defaultValue: PanelPlacement? = nil
}

/// Places each child at its `GridPlacementKey` (`calcGridItemPosition`); the
/// height is the rows the layout uses (`containerHeight`).
struct GridDashboardLayout: Layout {
  /// Only a measuring pass without a width uses it.
  static let fallbackWidth: CGFloat = 1200

  /// The frame of each placement in a container `width` points wide.
  static func frames(_ layout: [PanelPlacement], width: CGFloat) -> [ModuleID: CGRect] {
    var frames: [ModuleID: CGRect] = [:]
    for placement in layout {
      frames[placement.i] = DashboardLayoutEngine.frame(for: placement, containerWidth: width)
    }
    return frames
  }

  static func size(_ layout: [PanelPlacement], proposedWidth: CGFloat?) -> CGSize {
    let width: CGFloat
    if let proposedWidth, proposedWidth.isFinite {
      width = proposedWidth
    } else {
      width = fallbackWidth
    }
    return CGSize(width: width, height: DashboardLayoutEngine.contentHeight(layout))
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    Self.size(subviews.compactMap { $0[GridPlacementKey.self] }, proposedWidth: proposal.width)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    for subview in subviews {
      guard let placement = subview[GridPlacementKey.self] else {
        subview.place(at: bounds.origin, anchor: .topLeading, proposal: .zero)
        continue
      }
      let frame = DashboardLayoutEngine.frame(for: placement, containerWidth: bounds.width)
      subview.place(
        at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
        anchor: .topLeading,
        proposal: ProposedViewSize(frame.size)
      )
    }
  }
}

/// Where a dragged panel will land (`react-grid-placeholder`).
private struct GridPlaceholder: View {
  @Environment(\.theme) private var theme

  var body: some View {
    RoundedRectangle(cornerRadius: Radius.medium)
      .fill(theme.brandTint)
      .overlay {
        RoundedRectangle(cornerRadius: Radius.medium)
          .strokeBorder(theme.brand.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
      }
      .accessibilityHidden(true)
  }
}

/// One panel of the grid. Outside the arrange mode it is ordinary content:
/// only a 0.5 s hold (24 pt of slack) is read, alongside the panel's own
/// clicks. While arranging, a surface over the content takes the drags.
private struct GridPanelCell: View {
  @Environment(\.theme) private var theme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @GestureState private var pressing = false

  let module: ModuleID
  let content: AnyView
  let index: Int
  let arranging: Bool
  let isActive: Bool
  let offset: CGSize
  let begin: () -> Void
  let move: (DragGesture.Value) -> Void
  let resize: (DragGesture.Value) -> Void
  let end: () -> Void

  private var jiggles: Bool { arranging && !isActive && !reduceMotion }

  var body: some View {
    card
      // Always applied, so turning the jiggle on and off never rebuilds the panel.
      .keyframeAnimator(initialValue: 0.0, repeating: jiggles) { view, angle in
        view.rotationEffect(.degrees(angle))
      } keyframes: { _ in
        KeyframeTrack {
          CubicKeyframe(GridJiggle.angle, duration: GridJiggle.duration(index: index) / 2)
          CubicKeyframe(-GridJiggle.angle, duration: GridJiggle.duration(index: index) / 2)
        }
      }
      .offset(offset)
  }

  private var card: some View {
    content
      .padding(16)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .allowsHitTesting(!arranging)
      .clipShape(.rect(cornerRadius: Radius.medium))
      .glassSurface(.panel, elevation: isActive ? .e5 : nil)
      .overlay { outline }
      .overlay { if arranging { dragSurface } }
      .overlay(alignment: .bottomTrailing) { if arranging { resizeHandle } }
      .simultaneousGesture(hold, isEnabled: !arranging)
  }

  /// `panel-press`: the outline grows while the hold counts down; it stays on
  /// the panel being moved or resized.
  private var outline: some View {
    let visible = pressing || isActive
    return RoundedRectangle(cornerRadius: Radius.medium + 6)
      .strokeBorder(theme.brand.opacity(visible ? 1 : 0), lineWidth: 2)
      .padding(-6)
      .animation(pressing ? .linear(duration: 0.5) : nil, value: pressing)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
  }

  private var hold: some Gesture {
    LongPressGesture(minimumDuration: 0.5, maximumDistance: 24)
      .updating($pressing) { value, state, _ in
        state = value
      }
      .onEnded { _ in
        begin()
      }
  }

  private var dragSurface: some View {
    Color.clear
      .contentShape(.rect)
      .pointerStyle(isActive ? .grabActive : .grabIdle)
      .gesture(
        DragGesture(minimumDistance: 2, coordinateSpace: .named(GridDashboardView.coordinateSpace))
          .onChanged { move($0) }
          .onEnded { _ in end() }
      )
      .accessibilityHidden(true)
  }

  /// The south-east handle, the only one the web offers (`handles: ['se']`).
  private var resizeHandle: some View {
    Image(systemName: "arrow.down.right")
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(theme.inkMid)
      .frame(width: 28, height: 28)
      .contentShape(.rect)
      .pointerStyle(.frameResize(position: .bottomTrailing))
      .gesture(
        DragGesture(minimumDistance: 1, coordinateSpace: .named(GridDashboardView.coordinateSpace))
          .onChanged { resize($0) }
          .onEnded { _ in end() }
      )
      .help("Redimensionar")
      .accessibilityHidden(true)
  }
}

/// `panel-jiggle` (`app/globals.css:1065-1098`): ±0.4° with a different
/// period every second and third panel, so they do not shake in unison.
nonisolated enum GridJiggle {
  static let angle = 0.4

  static func duration(index: Int) -> Double {
    let position = index + 1
    if position.isMultiple(of: 3) { return 0.2 }
    if position.isMultiple(of: 2) { return 0.22 }
    return 0.18
  }
}
