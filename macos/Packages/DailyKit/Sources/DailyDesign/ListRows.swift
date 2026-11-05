import SwiftUI

// MARK: - List row

/// The row shell the web repeats in every list: `border-b border-line-soft px-2 py-3
/// even:bg-muted/25 hover:bg-brand-tint last:border-b-0` with `transition-colors
/// duration-100` (`JiraPanel.tsx:102-103`, `PullRow.tsx:31`, `SlackPanel.tsx:35`,
/// `EmailPanel.tsx:1320`, `AgendaPanel.tsx:164`).
public enum ListRowStyle {
  /// `px-2`.
  public static let horizontalPadding: CGFloat = 8
  /// `--muted` is not a Theme token; line-soft is its neighbour in every palette.
  public static let stripeOpacity: Double = 0.25

  /// CSS `:nth-child(even)` counts from 1, so the zebra falls on the odd 0-based
  /// indices: the second, fourth… row.
  public static func isStriped(index: Int) -> Bool { index % 2 == 1 }

  /// The row fill. Open (`isOpen ? 'bg-brand-tint'`, `EmailPanel.tsx:1321`) and hover
  /// both replace the stripe, as a later `background-color` does in CSS.
  public static func background(index: Int, hovering: Bool, isActive: Bool, theme: Theme) -> Color {
    if isActive || hovering { return theme.brandTint }
    return isStriped(index: index) ? theme.lineSoft.opacity(stripeOpacity) : .clear
  }
}

/// One row of a module list. `index` is the 0-based position in the list, for the
/// zebra; `isLast` drops the divider (`last:border-b-0`). The vertical padding follows
/// the density (`py-3`, compact `py-2`), unless the caller passes the web's own value
/// (the agenda uses `py-2` in both, `AgendaPanel.tsx:164`).
public struct ListRow<Content: View>: View {
  @Environment(\.theme) private var theme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hovering = false
  private let index: Int
  private let isLast: Bool
  private let isActive: Bool
  private let verticalPadding: CGFloat?
  private let content: Content

  public init(
    index: Int,
    isLast: Bool = false,
    isActive: Bool = false,
    verticalPadding: CGFloat? = nil,
    @ViewBuilder content: () -> Content
  ) {
    self.index = index
    self.isLast = isLast
    self.isActive = isActive
    self.verticalPadding = verticalPadding
    self.content = content()
  }

  public var body: some View {
    content
      .padding(.horizontal, ListRowStyle.horizontalPadding)
      .padding(.vertical, verticalPadding ?? theme.metrics.rowVerticalPadding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(ListRowStyle.background(index: index, hovering: hovering, isActive: isActive, theme: theme))
      .overlay(alignment: .bottom) {
        if !isLast {
          Rectangle().fill(theme.lineSoft).frame(height: 1).accessibilityHidden(true)
        }
      }
      .contentShape(.rect)
      .onHover { hovering = $0 }
      .animation(Motion.ease(Motion.fast, reduceMotion: reduceMotion), value: hovering)
      .accessibilityElement(children: .contain)
  }
}

// MARK: - Active row

/// The selected row of a tree or result list (`components/notes/NoteTree.tsx:143-149`):
/// a brand-tint gradient fading out at 85% and a 3pt brand bar on the leading edge,
/// which glows in dark (`dark:before:shadow-[0_0_8px_0_var(--brand)]`). At rest the
/// row is `text-ink-mid hover:bg-glass-line hover:text-ink`.
public enum ActiveRowStyle {
  /// `before:w-[3px]`.
  public static let barWidth: CGFloat = 3
  /// `transparent_85%`.
  public static let gradientEnd: CGFloat = 0.85

  public static func foreground(isActive: Bool, hovering: Bool, theme: Theme) -> Color {
    isActive || hovering ? theme.ink : theme.inkMid
  }

  /// The hover fill of a row that is not active. `--glass-line` is not a Theme token;
  /// line-soft is the closest hairline colour in every palette.
  public static func hoverFill(theme: Theme) -> Color { theme.lineSoft }

  /// The glow radius of the bar: `0 0 8px` in dark, none in light.
  public static func barGlowRadius(scheme: ColorScheme) -> CGFloat { scheme == .dark ? 4 : 0 }
}

extension View {
  /// Marks a row as the active one of its list, the web's selection in place of the
  /// system's (spec 013 FR-013-07). Also sets the text colour and the selected trait.
  public func activeRow(_ isActive: Bool) -> some View {
    modifier(ActiveRowModifier(isActive: isActive))
  }
}

private struct ActiveRowModifier: ViewModifier {
  @Environment(\.theme) private var theme
  @Environment(\.colorScheme) private var scheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hovering = false
  let isActive: Bool

  func body(content: Content) -> some View {
    content
      .foregroundStyle(ActiveRowStyle.foreground(isActive: isActive, hovering: hovering, theme: theme))
      .background {
        if isActive {
          LinearGradient(
            stops: [
              .init(color: theme.brandTint, location: 0),
              .init(color: theme.brandTint.opacity(0), location: ActiveRowStyle.gradientEnd),
            ],
            startPoint: .leading,
            endPoint: .trailing
          )
        } else if hovering {
          ActiveRowStyle.hoverFill(theme: theme)
        }
      }
      .overlay(alignment: .leading) {
        if isActive {
          Rectangle()
            .fill(theme.brand)
            .frame(width: ActiveRowStyle.barWidth)
            .shadow(color: theme.brand, radius: ActiveRowStyle.barGlowRadius(scheme: scheme))
            .accessibilityHidden(true)
        }
      }
      .contentShape(.rect)
      .onHover { hovering = $0 }
      .animation(Motion.ease(Motion.fast, reduceMotion: reduceMotion), value: hovering)
      .accessibilityAddTraits(isActive ? .isSelected : [])
  }
}
