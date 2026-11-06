import DailyDesign
import DailyModels
import SwiftUI

// The pieces of the Abas workspace, drawn after Trellis' theme as the web
// overrides it for the home page (`app/globals.css` `.home-workspace .trellis`):
// transparent tab bar, the selected tab on `--glass-strong`, `--primary` accent,
// `--brand-tint` drop slots, radius `--radius + 5px`.

/// Places each child at the rect it carries in `WorkspaceCanvasFrame`, so the
/// workspace is positioned from `WorkspaceGeometry` like Trellis' absolute
/// layout, and frames read in the canvas' coordinate space are real layout frames.
struct WorkspaceCanvas: Layout {
  /// The size the geometry was computed for.
  let size: CGSize

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    size
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    for subview in subviews {
      let rect = subview[WorkspaceCanvasFrame.self]
      subview.place(
        at: CGPoint(x: bounds.minX + rect.minX, y: bounds.minY + rect.minY),
        anchor: .topLeading,
        proposal: ProposedViewSize(width: rect.width, height: rect.height)
      )
    }
  }
}

// Nonisolated: the key is read by SwiftUI's layout machinery, not only on the main actor.
nonisolated struct WorkspaceCanvasFrame: LayoutValueKey {
  static let defaultValue: CGRect = .zero
}

extension View {
  /// Sizes the view to `rect` and tells `WorkspaceCanvas` where to put it.
  func workspaceCanvasFrame(_ rect: CGRect) -> some View {
    frame(width: max(0, rect.width), height: max(0, rect.height))
      .layoutValue(key: WorkspaceCanvasFrame.self, value: rect)
  }
}

enum WorkspaceChrome {
  /// The canvas' coordinate space: tab frames and drag locations are read in it.
  nonisolated static let coordinateSpace = "workspace-tabs"
  /// `--trellis-radius` as the home page sets it: `--radius + 5px`.
  static let groupRadius: CGFloat = Radius.extraLarge
  /// `--trellis-tab-inset`.
  static let tabInset: CGFloat = 4
  /// Concentric with the group the tabs sit `tabInset` inside of; Trellis'
  /// fixed `--trellis-tab-radius` (7px) left a visibly flatter curve there.
  static let tabRadius: CGFloat = Radius.nested(groupRadius, inset: tabInset)
  /// The `HStack` spacing between tabs, which the in-strip sort packs with too.
  static let tabSpacing: CGFloat = 2
  static let tabMinWidth: CGFloat = 72
  static let tabMaxWidth: CGFloat = 220
  /// `--trellis-font-size` on the home page: 0.8125rem.
  static let tabFontSize: CGFloat = 13

  /// `[data-sorting]`: `transform 180ms cubic-bezier(0.2, 0.8, 0.2, 1)`, the
  /// siblings sliding aside while a tab is reordered in its strip.
  static func sortAnimation(reduceMotion: Bool) -> Animation? {
    reduceMotion ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.18)
  }
}

/// A tab's part in a drag: following the pointer inside its strip
/// (`[data-dragging]`, on top and fully drawn), or left behind dimmed while a
/// ghost carries it elsewhere.
enum WorkspaceTabDragRole: Equatable {
  case none
  case following
  case leftBehind
}

/// One tab (`[data-trellis-part="tab"]`): muted until hovered or selected; the
/// selected one joins the panel below and, in the focused group, carries the
/// accent along its top. Not closable (`closable={false}`).
struct WorkspaceTabButton: View {
  @Environment(\.theme) private var theme
  @State private var hovering = false
  let title: String
  let isSelected: Bool
  let isInFocusedGroup: Bool
  let dragRole: WorkspaceTabDragRole
  let select: () -> Void

  var body: some View {
    let shape = UnevenRoundedRectangle(
      topLeadingRadius: WorkspaceChrome.tabRadius, topTrailingRadius: WorkspaceChrome.tabRadius)
    Button(action: select) {
      Text(title)
        .font(.daily(size: WorkspaceChrome.tabFontSize, weight: .medium))
        .lineLimit(1)
        .truncationMode(.tail)
        .foregroundStyle(isSelected || hovering || dragRole == .following ? theme.ink : theme.inkMid)
        .padding(.horizontal, 10)
        .frame(minWidth: WorkspaceChrome.tabMinWidth, maxWidth: WorkspaceChrome.tabMaxWidth, maxHeight: .infinity)
        .background(fill)
        .overlay(alignment: .top) {
          if isSelected && isInFocusedGroup {
            Rectangle().fill(theme.brand).frame(height: 2)
          }
        }
        .clipShape(shape)
        .contentShape(shape)
    }
    .buttonStyle(.plain)
    .opacity(dragRole == .leftBehind ? 0.45 : 1)
    .onHover { hovering = $0 }
    .accessibilityLabel("aba \(title)")
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
  }

  private var fill: Color {
    if isSelected || dragRole == .following { return theme.surface3 }
    return hovering ? theme.lineSoft : .clear
  }
}

/// A split's divider (`[data-trellis-part="divider"]`): invisible until hovered,
/// then an accent bar; resize cursor along its axis. `isActive` (resizing, or
/// focused from the keyboard) shows the bar in full.
struct WorkspaceDividerHandle: View {
  @Environment(\.theme) private var theme
  @State private var hovering = false
  let axis: WorkspaceAxis
  let isActive: Bool

  var body: some View {
    ZStack {
      Rectangle().fill(.clear).contentShape(Rectangle())
      Capsule()
        .fill(theme.brand)
        .frame(width: axis == .x ? 3 : nil, height: axis == .y ? 3 : nil)
        .opacity(isActive ? 1 : hovering ? 0.8 : 0)
    }
    .onHover { hovering = $0 }
    .pointerStyle(cursor)
  }

  private var cursor: PointerStyle {
    axis == .x ? .columnResize : .rowResize
  }
}

/// Where the dragged tab would land (`drop-slot`): a bar between tabs, or the
/// slot the new group would take, or the whole group it would join.
struct WorkspaceDropIndicator: View {
  @Environment(\.theme) private var theme
  let target: TabDropTarget

  var body: some View {
    switch target {
    case .strip:
      Capsule().fill(theme.brand)
    case .edge, .group:
      RoundedRectangle(cornerRadius: WorkspaceChrome.groupRadius)
        .fill(theme.brandTint.opacity(0.7))
        .overlay {
          RoundedRectangle(cornerRadius: WorkspaceChrome.groupRadius).strokeBorder(theme.brand, lineWidth: 2)
        }
    }
  }
}

/// The tab that follows the pointer while it is dragged.
struct WorkspaceDragGhost: View {
  @Environment(\.theme) private var theme
  let title: String

  var body: some View {
    Text(title)
      .font(.daily(size: WorkspaceChrome.tabFontSize, weight: .medium))
      .lineLimit(1)
      .foregroundStyle(theme.ink)
      .padding(.horizontal, 12)
      .frame(height: 28)
      .glassSurface(.pill)
  }
}
