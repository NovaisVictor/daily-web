import AppKit
import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// The wide Início grid (`components/DashboardGrid.tsx`): 12 columns, rows of
/// 32 pt and gaps of 24 pt, each panel on the glass panel surface. Holding a
/// panel for 0.5 s starts the arrange mode, where dragging moves a panel and
/// the bottom-right handle resizes it.
///
/// While a gesture lasts the dragged panel follows the pointer on its own
/// (only it reads `GridPointer`), the placeholder sits on the cell it would
/// land on, and the other panels only move, eased, when that cell changes.
struct GridDashboardView: View {
  static let coordinateSpace = "GridDashboard"
  /// Room under the last panel while arranging (`pb-28`), so the floating bar
  /// never covers a resize handle.
  static let arrangingBottomPadding: CGFloat = 112
  /// `react-grid-layout`'s `transition: transform 200ms ease`.
  static let settleDuration: TimeInterval = 0.2

  let window: HomeWindowState
  let panel: (ModuleID) -> AnyView

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var containerWidth: CGFloat = 0
  @FocusState private var focusedPanel: ModuleID?
  /// The panel whose hold started the mode: it takes the keyboard focus.
  @State private var heldPanel: ModuleID?

  var body: some View {
    let grid = window.grid
    let layout = window.gridLayout
    let arranging = grid.isArranging
    let session = grid.session
    let swing = GridJiggle.angle(arranging: arranging, active: session != nil, reduceMotion: reduceMotion)
    let actions = cellActions
    GridDashboardLayout(minimumHeight: session?.startContentHeight ?? 0) {
      if let session, let target = layout.first(where: { $0.i == session.module }) {
        GridPlaceholder()
          .layoutValue(key: GridPlacementKey.self, value: target)
      }
      ForEach(Array(layout.enumerated()), id: \.element.i) { index, placement in
        let follow = followState(of: placement.i, in: session)
        GridPanelCell(
          module: placement.i,
          content: panel(placement.i),
          index: index,
          arranging: arranging,
          swing: swing,
          follow: follow,
          isFocused: focusedPanel == placement.i,
          pointer: grid.pointer,
          actions: actions
        )
        .focusable(arranging)
        .focused($focusedPanel, equals: placement.i)
        .focusEffectDisabled()
        .onKeyPress(phases: [.down, .repeat]) { press in handleKey(press, module: placement.i) }
        // The followed panel stays on the cell it started from and moves by
        // its offset, so the eased re-layout never pulls it from the pointer.
        .layoutValue(
          key: GridPlacementKey.self, value: follow == nil ? placement : (session?.startPlacement ?? placement)
        )
        .zIndex(follow == nil ? 0 : 2)
      }
    }
    // Keyed on the layout and the dragged panel only: a pointer event that
    // keeps the cell changes neither, so nothing else animates under it. The
    // end of a gesture changes the key, which settles the panel into place.
    .animation(
      Motion.ease(Self.settleDuration, reduceMotion: reduceMotion),
      value: GridMotionKey(layout: layout, dragged: session?.module)
    )
    .coordinateSpace(.named(Self.coordinateSpace))
    .onGeometryChange(for: CGFloat.self) { proxy in
      proxy.size.width
    } action: { width in
      containerWidth = width
    }
    .padding(.bottom, arranging ? Self.arrangingBottomPadding : 0)
    .onChange(of: arranging) {
      let first = GridKeyboard.next(after: nil, in: window.gridLayout, backwards: false)
      focusedPanel = arranging ? (heldPanel ?? first) : nil
      heldPanel = nil
    }
    .onDisappear { window.cancelPanelGesture() }
  }

  /// One set of actions for every cell; they only capture the window and
  /// this view's state, so an older copy a cell holds still acts right.
  private var cellActions: GridCellActions {
    GridCellActions(
      begin: { module in
        heldPanel = module
        window.beginArranging()
      },
      drag: { module, kind, value in drag(module, kind, value) },
      end: { window.endPanelGesture() }
    )
  }

  private func drag(_ module: ModuleID, _ kind: GridDragSession.Kind, _ value: DragGesture.Value) {
    let changed = window.dragPanel(
      module, kind: kind, startLocation: value.startLocation, translation: value.translation,
      containerWidth: containerWidth)
    // The trackpad taps as the placeholder snaps, the way macOS marks alignment.
    if changed { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
  }

  private func followState(of module: ModuleID, in session: GridDragSession?) -> GridFollow? {
    guard let session, session.module == module else { return nil }
    let start = session.startPlacement
    let smallest = PanelPlacement(
      i: module, x: start.x, y: start.y, w: DashboardLayoutEngine.minimumWidth, h: DashboardLayoutEngine.minimumHeight)
    let tallest = PanelPlacement(i: module, x: start.x, y: start.y, w: start.w, h: DashboardLayoutEngine.maximumHeight)
    let minimum = DashboardLayoutEngine.frame(for: smallest, containerWidth: containerWidth).size
    let maximum = CGSize(
      width: max(minimum.width, containerWidth - session.startFrame.minX),
      height: DashboardLayoutEngine.frame(for: tallest, containerWidth: containerWidth).height)
    return GridFollow(
      kind: session.kind, startSize: session.startFrame.size, minimumSize: minimum, maximumSize: maximum)
  }

  private func handleKey(_ press: KeyPress, module: ModuleID) -> KeyPress.Result {
    guard window.grid.isArranging else { return .ignored }
    let shift = press.modifiers.contains(.shift)
    // AppKit delivers Shift-Tab as the back-tab character.
    let backTab = press.characters == "\u{19}"
    if press.key == .tab || backTab {
      focusedPanel = GridKeyboard.next(after: module, in: window.gridLayout, backwards: shift || backTab)
      return .handled
    }
    guard let step = Self.arrowStep(press.key) else { return .ignored }
    window.nudgePanel(module, dx: step.dx, dy: step.dy, resizing: shift)
    return .handled
  }

  private static func arrowStep(_ key: KeyEquivalent) -> (dx: Int, dy: Int)? {
    if key == .leftArrow { return (-1, 0) }
    if key == .rightArrow { return (1, 0) }
    if key == .upArrow { return (0, -1) }
    if key == .downArrow { return (0, 1) }
    return nil
  }
}

/// What a cell asks of the grid.
struct GridCellActions {
  let begin: (ModuleID) -> Void
  let drag: (ModuleID, GridDragSession.Kind, DragGesture.Value) -> Void
  let end: () -> Void
}

/// What the grid's animation follows.
private struct GridMotionKey: Equatable {
  let layout: [PanelPlacement]
  let dragged: ModuleID?
}

/// How the panel under a gesture follows the pointer: moved by the pointer's
/// translation, or resized to it within the panel limits and the grid's edge.
nonisolated struct GridFollow: Equatable, Sendable {
  let kind: GridDragSession.Kind
  let startSize: CGSize
  let minimumSize: CGSize
  let maximumSize: CGSize

  func size(for translation: CGSize) -> CGSize {
    CGSize(
      width: min(max(startSize.width + translation.width, minimumSize.width), maximumSize.width),
      height: min(max(startSize.height + translation.height, minimumSize.height), maximumSize.height))
  }
}

/// Each grid child's place, in grid units.
nonisolated struct GridPlacementKey: LayoutValueKey {
  static let defaultValue: PanelPlacement? = nil
}

/// Places each child at its `GridPlacementKey` (`calcGridItemPosition`); the
/// height is the rows the layout uses (`containerHeight`), and never less
/// than `minimumHeight`.
struct GridDashboardLayout: Layout {
  /// Only a measuring pass without a width uses it.
  static let fallbackWidth: CGFloat = 1200

  /// The grid's height when a gesture began, while it lasts: a grid that got
  /// shorter would scroll the page under a still pointer.
  var minimumHeight: CGFloat = 0

  /// The frame of each placement in a container `width` points wide.
  static func frames(_ layout: [PanelPlacement], width: CGFloat) -> [ModuleID: CGRect] {
    var frames: [ModuleID: CGRect] = [:]
    for placement in layout {
      frames[placement.i] = DashboardLayoutEngine.frame(for: placement, containerWidth: width)
    }
    return frames
  }

  static func size(_ layout: [PanelPlacement], proposedWidth: CGFloat?, minimumHeight: CGFloat = 0) -> CGSize {
    let width: CGFloat
    if let proposedWidth, proposedWidth.isFinite {
      width = proposedWidth
    } else {
      width = fallbackWidth
    }
    return CGSize(width: width, height: max(DashboardLayoutEngine.contentHeight(layout), minimumHeight))
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    Self.size(
      subviews.compactMap { $0[GridPlacementKey.self] }, proposedWidth: proposal.width, minimumHeight: minimumHeight)
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

/// Where a dragged panel will land (`.react-grid-placeholder`, globals.css).
private struct GridPlaceholder: View {
  @Environment(\.theme) private var theme

  var body: some View {
    RoundedRectangle(cornerRadius: Radius.extraLarge)
      .fill(theme.brandTint)
      .accessibilityHidden(true)
  }
}

/// One panel of the grid. Outside the arrange mode it is ordinary content:
/// only a 0.5 s hold (24 pt of slack) is read, alongside the panel's own
/// clicks. While arranging, a surface over the content takes the drags.
private struct GridPanelCell: View {
  @Environment(\.theme) private var theme
  @GestureState private var pressing = false
  @State private var hovering = false
  @State private var hover = GridHoverLocation()
  @State private var hold: GridHoldStart?

  let module: ModuleID
  let content: AnyView
  let index: Int
  let arranging: Bool
  /// The jiggle's tilt; 0 keeps the panel exactly upright.
  let swing: Double
  /// Set on the panel under a gesture.
  let follow: GridFollow?
  let isFocused: Bool
  let pointer: GridPointer
  let actions: GridCellActions

  var body: some View {
    card
      // Always applied, so turning the jiggle on and off never rebuilds the
      // panel. The animator swings a phase and `swing` scales it: whatever
      // phase it stops on, a zero swing leaves no tilt behind.
      .keyframeAnimator(initialValue: 0.0, repeating: swing != 0) { view, phase in
        view.rotationEffect(.degrees(phase * swing))
      } keyframes: { _ in
        KeyframeTrack {
          CubicKeyframe(1, duration: GridJiggle.duration(index: index) / 2)
          CubicKeyframe(-1, duration: GridJiggle.duration(index: index) / 2)
        }
      }
      .modifier(GridMoveOffset(pointer: pointer, follow: follow))
      .overlay(alignment: .topLeading) { holdBadge }
      // The panel under the pointer is never eased: it would trail behind it.
      .transaction { transaction in
        if follow != nil { transaction.animation = nil }
      }
  }

  private var card: some View {
    content
      .padding(16)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .modifier(GridResizeFrame(pointer: pointer, follow: follow))
      .allowsHitTesting(!arranging)
      .clipShape(.rect(cornerRadius: Radius.medium))
      .glassSurface(.panel)
      // A plain shadow for the lifted panel: the blurred `.e5` elevation
      // redrew a 48 pt blur on every pointer event.
      .shadow(
        color: follow == nil ? Color.clear : Color.black.opacity(0.22),
        radius: follow == nil ? 0 : 14,
        y: follow == nil ? 0 : 8
      )
      .overlay { pressRing }
      .overlay { if arranging { arrangeOutline } }
      .overlay { if arranging { dragSurface } }
      .overlay(alignment: .bottomTrailing) { if arranging { resizeHandle } }
      .onContinuousHover(coordinateSpace: .local) { phase in
        if case .active(let location) = phase { hover.point = location }
      }
      .simultaneousGesture(holdGesture, isEnabled: !arranging)
      .onChange(of: pressing) {
        hold = pressing ? GridHoldStart(date: .now, point: hover.point) : nil
      }
  }

  /// `panel-press`: a brand ring grows around the panel while the hold counts down.
  private var pressRing: some View {
    RoundedRectangle(cornerRadius: Radius.medium + 6)
      .strokeBorder(theme.brand.opacity(pressing ? 1 : 0), lineWidth: 2)
      .padding(-6)
      .animation(pressing ? .linear(duration: Motion.press) : nil, value: pressing)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
  }

  /// `outline: 1px dashed var(--line-strong)` 0.5rem out, `--brand-edge` on
  /// hover, the brand on the panel being moved or focused.
  private var arrangeOutline: some View {
    let color: Color
    if follow != nil || isFocused {
      color = theme.brand
    } else if hovering {
      color = theme.brandEdge
    } else {
      color = theme.lineStrong
    }
    return RoundedRectangle(cornerRadius: Radius.medium + 8)
      .strokeBorder(color, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
      .padding(-8)
      .dailyAnimation(Motion.hover, value: color)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
  }

  private var holdGesture: some Gesture {
    LongPressGesture(minimumDuration: GridHold.duration, maximumDistance: GridHold.slop)
      .updating($pressing) { value, state, _ in
        state = value
      }
      .onEnded { _ in
        actions.begin(module)
      }
  }

  /// "Segure para organizar · 0,4 s" beside the pointer (`DashboardGrid.tsx:347-356`).
  @ViewBuilder private var holdBadge: some View {
    if let hold {
      GridHoldBadge(start: hold.date)
        .offset(x: hold.point.x + GridHold.badgeOffset, y: hold.point.y + GridHold.badgeOffset)
    }
  }

  private var dragSurface: some View {
    Color.clear
      .contentShape(.rect)
      .pointerStyle(follow?.kind == .move ? .grabActive : .grabIdle)
      .onHover { hovering = $0 }
      .gesture(
        DragGesture(minimumDistance: 2, coordinateSpace: .named(GridDashboardView.coordinateSpace))
          .onChanged { actions.drag(module, .move, $0) }
          .onEnded { _ in actions.end() }
      )
      .accessibilityHidden(true)
  }

  /// The south-east handle, the only one the web offers (`handles: ['se']`):
  /// a 9 pt corner in the brand colour (globals.css `.react-resizable-handle`),
  /// on a 28 pt target that is easier to catch than the drawing.
  private var resizeHandle: some View {
    GridResizeCorner()
      .stroke(theme.brand, lineWidth: 2)
      .frame(width: 9, height: 9)
      // The web's handle sits 2 px in and draws its corner 3 px further.
      .padding(5)
      .frame(width: 28, height: 28, alignment: .bottomTrailing)
      .contentShape(.rect)
      .pointerStyle(.frameResize(position: .bottomTrailing))
      .gesture(
        DragGesture(minimumDistance: 1, coordinateSpace: .named(GridDashboardView.coordinateSpace))
          .onChanged { actions.drag(module, .resize, $0) }
          .onEnded { _ in actions.end() }
      )
      .help("Redimensionar")
      .accessibilityHidden(true)
  }
}

/// Moves the panel under a move gesture by the pointer's translation. Only
/// that panel reads the pointer, so only it redraws on every event.
private struct GridMoveOffset: ViewModifier {
  let pointer: GridPointer
  let follow: GridFollow?

  func body(content: Content) -> some View {
    content.offset(follow?.kind == .move ? pointer.translation : .zero)
  }
}

/// Sizes the panel under a resize gesture to the pointer, while the
/// placeholder shows the grid size it will snap to.
private struct GridResizeFrame: ViewModifier {
  let pointer: GridPointer
  let follow: GridFollow?

  func body(content: Content) -> some View {
    let size = follow?.kind == .resize ? follow?.size(for: pointer.translation) : nil
    content.frame(width: size?.width, height: size?.height, alignment: .topLeading)
  }
}

/// The resize handle's corner: the right and bottom borders of a 9 pt box
/// with the web's 2 px rounding where they meet.
private struct GridResizeCorner: Shape {
  func path(in rect: CGRect) -> Path {
    // Half the 2 pt stroke, so the line stays inside the box as a CSS border does.
    let inset: CGFloat = 1
    let right = rect.maxX - inset
    let bottom = rect.maxY - inset
    var path = Path()
    path.move(to: CGPoint(x: right, y: rect.minY))
    path.addArc(
      tangent1End: CGPoint(x: right, y: bottom), tangent2End: CGPoint(x: rect.minX, y: bottom),
      radius: Radius.hairline)
    path.addLine(to: CGPoint(x: rect.minX, y: bottom))
    return path
  }
}

/// Where the pointer last hovered a panel. A plain reference, not observed:
/// it changes on every mouse move and is only read when a press starts.
private final class GridHoverLocation {
  var point: CGPoint = .zero
}

private struct GridHoldStart: Equatable {
  let date: Date
  let point: CGPoint
}

/// The countdown beside the pointer while a panel is held.
private struct GridHoldBadge: View {
  @Environment(\.theme) private var theme
  let start: Date

  var body: some View {
    TimelineView(.periodic(from: start, by: 0.1)) { context in
      Text(GridHold.badgeText(elapsed: context.date.timeIntervalSince(start)))
        .typeRole(.caption)
        .monospacedDigit()
        .foregroundStyle(theme.inkMid)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .glassSurface(.pill, elevation: .e3)
    }
    .fixedSize()
    .allowsHitTesting(false)
    // `aria-live="off"` on the web: a pointer aid, not news.
    .accessibilityHidden(true)
  }
}

/// The hold that starts the arrange mode (`HOLD_MS`, `HOLD_SLOP_PX`).
nonisolated enum GridHold {
  static let duration: TimeInterval = Motion.press
  static let slop: CGFloat = 24
  /// The badge's distance from the pointer (`left: holding.x + 18`).
  static let badgeOffset: CGFloat = 18

  /// `Segure para organizar · ${(remaining / 1000).toFixed(1)} s`, with the
  /// Brazilian decimal comma.
  static func badgeText(elapsed: TimeInterval) -> String {
    let remaining = max(duration - max(elapsed, 0), 0)
    let tenths = Int((remaining * 10).rounded())
    return "Segure para organizar · \(tenths / 10),\(tenths % 10) s"
  }
}

/// `panel-jiggle` (`app/globals.css:1065-1098`): ±0.4° with a different
/// period every second and third panel, so they do not shake in unison.
nonisolated enum GridJiggle {
  static let amplitude = 0.4

  /// The tilt the jiggle swings to. None outside the arrange mode, with
  /// Reduce Motion, or while a gesture is in progress: the web keeps the
  /// dragged panel still, and pausing the others too spares redrawing every
  /// glass panel on each pointer event.
  static func angle(arranging: Bool, active: Bool, reduceMotion: Bool) -> Double {
    arranging && !active && !reduceMotion ? amplitude : 0
  }

  static func duration(index: Int) -> Double {
    let position = index + 1
    if position.isMultiple(of: 3) { return 0.2 }
    if position.isMultiple(of: 2) { return 0.22 }
    return 0.18
  }
}
