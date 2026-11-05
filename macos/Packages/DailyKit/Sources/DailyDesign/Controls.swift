import AppKit
import SwiftUI

/// A row of filter controls that wraps instead of collapsing (`components/ui/FilterBar.tsx`).
/// The web marks it `role="search"` with an `aria-label`; here the label names the group.
public struct FilterBar<Content: View>: View {
  private let label: String
  private let content: Content

  public init(_ label: String, @ViewBuilder content: () -> Content) {
    self.label = label
    self.content = content()
  }

  public var body: some View {
    FlowLayout(spacing: 8) { content }
      .padding(.bottom, 12)
      .accessibilityElement(children: .contain)
      .accessibilityLabel(label)
  }
}

/// Lays children out left to right and wraps them onto new lines, like `flex-wrap`.
public struct FlowLayout: Layout {
  public var spacing: CGFloat

  public init(spacing: CGFloat = 8) {
    self.spacing = spacing
  }

  public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
    let width = rows.map(\.width).max() ?? 0
    let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
    return CGSize(width: width, height: height)
  }

  public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    var y = bounds.minY
    for row in arrange(width: bounds.width, subviews: subviews) {
      var x = bounds.minX
      for index in row.indices {
        let size = subviews[index].sizeThatFits(.unspecified)
        subviews[index].place(
          at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
          proposal: ProposedViewSize(size)
        )
        x += size.width + spacing
      }
      y += row.height + spacing
    }
  }

  private struct Row {
    var indices: [Int] = []
    var width: CGFloat = 0
    var height: CGFloat = 0
  }

  private func arrange(width maxWidth: CGFloat, subviews: Subviews) -> [Row] {
    var rows: [Row] = []
    var current = Row()
    for index in subviews.indices {
      let size = subviews[index].sizeThatFits(.unspecified)
      let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
      if needed > maxWidth, !current.indices.isEmpty {
        rows.append(current)
        current = Row()
      }
      current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
      current.height = max(current.height, size.height)
      current.indices.append(index)
    }
    if !current.indices.isEmpty { rows.append(current) }
    return rows
  }
}

/// A filter toggle (`components/ui/Chip.tsx`): `h-8 rounded-full border px-3.5 text-sm`.
/// Lit is `border-brand-edge bg-brand-tint text-ink shadow-control`, the neutral rim
/// rather than the accent one: a chip that is on is a control, not an action. Off is
/// `border-line-strong bg-surface-2 text-ink-mid shadow-e1`, with `hover:bg-accent`.
///
/// It is focusable by itself (not only with Full Keyboard Access), answers Space and
/// Return, and reports itself as a toggle to VoiceOver, like `aria-pressed`.
public struct Chip: View {
  @Environment(\.theme) private var theme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @FocusState private var focused: Bool
  @State private var hovering = false
  private let title: String
  private let isOn: Bool
  private let isDisabled: Bool
  private let action: () -> Void

  public init(_ title: String, isOn: Bool, isDisabled: Bool = false, action: @escaping () -> Void) {
    self.title = title
    self.isOn = isOn
    self.isDisabled = isDisabled
    self.action = action
  }

  public var body: some View {
    let palette = Self.palette(isOn: isOn, hovering: hovering, theme: theme)
    Text(title)
      .font(.daily(size: 14))
      .lineLimit(1)
      .foregroundStyle(palette.foreground)
      .padding(.horizontal, 14)
      .frame(height: theme.metrics.controlHeight)
      .pillSurface(palette, in: Capsule())
      .dailyFocusRing(focused, in: Capsule())
      .contentShape(.capsule)
      .opacity(isDisabled ? 0.5 : 1)
      // `transition-colors duration-100`.
      .animation(Motion.ease(Motion.fast, reduceMotion: reduceMotion), value: isOn)
      .animation(Motion.ease(Motion.fast, reduceMotion: reduceMotion), value: hovering)
      .focusable(!isDisabled)
      .focused($focused)
      .focusEffectDisabled()
      .onHover { hovering = $0 && !isDisabled }
      .onTapGesture(perform: trigger)
      .onKeyPress(keys: [.space, .return]) { _ in
        trigger()
        return .handled
      }
      .accessibilityElement()
      .accessibilityLabel(title)
      .accessibilityAddTraits(isOn ? [.isToggle, .isSelected] : .isToggle)
      .accessibilityAction(.default, trigger)
  }

  /// The colours of a chip in each state. `--accent` is not a Theme token; line-soft
  /// is its neighbour in every palette and stands in for it.
  static func palette(isOn: Bool, hovering: Bool, theme: Theme) -> PillPalette {
    if isOn {
      return PillPalette(fill: theme.brandTint, foreground: theme.ink, border: theme.brandEdge, shadow: .control)
    }
    return PillPalette(
      fill: hovering ? theme.lineSoft : theme.surface2,
      foreground: hovering ? theme.ink : theme.inkMid,
      border: theme.lineStrong,
      shadow: .e1
    )
  }

  private func trigger() {
    guard !isDisabled else { return }
    action()
  }
}

/// A search box (`components/ui/SearchInput.tsx`): a capsule with the magnifier inside.
/// Escape clears it, as a browser `type="search"` input does.
public struct SearchField: View {
  @Environment(\.theme) private var theme
  @FocusState private var focused: Bool
  @Binding private var text: String
  private let label: String
  private let placeholder: String

  public init(text: Binding<String>, label: String, placeholder: String = "buscar") {
    _text = text
    self.label = label
    self.placeholder = placeholder
  }

  public var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 13))
        .foregroundStyle(theme.inkDim)
        .accessibilityHidden(true)
      TextField(label, text: $text, prompt: Text(placeholder).foregroundStyle(theme.inkDim))
        .textFieldStyle(.plain)
        .font(.daily(size: 14))
        .foregroundStyle(theme.ink)
        .focused($focused)
        .accessibilityLabel(label)
        .onKeyPress(.escape) {
          guard !text.isEmpty else { return .ignored }
          text = ""
          return .handled
        }
    }
    .padding(.horizontal, 14)
    .frame(minWidth: 180, maxWidth: 320)
    .frame(height: theme.metrics.controlHeight)
    .background(theme.surface2, in: .capsule)
    .overlay { Capsule().strokeBorder(focused ? theme.brand : theme.lineStrong) }
    .overlay {
      Capsule()
        .strokeBorder(theme.brand.opacity(0.5), lineWidth: 3)
        .padding(-3)
        .opacity(focused ? 1 : 0)
    }
  }
}

/// A person's picture, or their initials (`components/ui/avatar.tsx`). The caller
/// decodes the server's data URL and passes the bytes.
public struct Avatar: View {
  @Environment(\.theme) private var theme
  private let name: String
  private let imageData: Data?
  private let size: CGFloat

  public init(name: String, imageData: Data? = nil, size: CGFloat = 32) {
    self.name = name
    self.imageData = imageData
    self.size = size
  }

  public var body: some View {
    Group {
      // Bytes that do not decode fall back to initials, as Radix's AvatarFallback
      // does when the image fails to load: a broken picture is not an error to show.
      if let imageData, let image = NSImage(data: imageData) {
        Image(nsImage: image)
          .resizable()
          .scaledToFill()
      } else {
        Text(Self.initials(for: name))
          .font(.daily(size: size * 0.4, weight: .medium))
          .foregroundStyle(theme.inkDim)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(theme.neutralTint)
      }
    }
    .frame(width: size, height: size)
    .clipShape(.circle)
    .accessibilityElement()
    .accessibilityLabel(name)
    .accessibilityAddTraits(.isImage)
  }

  /// Up to two initials: the first letter of the first and of the last word.
  public static func initials(for name: String) -> String {
    let words = name.split(whereSeparator: \.isWhitespace)
    guard let first = words.first?.first else { return "" }
    guard words.count > 1, let last = words.last?.first else { return String(first).uppercased() }
    return (String(first) + String(last)).uppercased()
  }
}

/// The header of a topic block (`components/ui/Section.tsx` and the Panel title):
/// title, an optional count in tabular figures, and trailing actions.
public struct SectionHeader<Actions: View>: View {
  @Environment(\.theme) private var theme
  private let title: String
  private let count: String?
  private let compact: Bool
  private let actions: Actions

  public init(
    _ title: String,
    count: String? = nil,
    compact: Bool = false,
    @ViewBuilder actions: () -> Actions
  ) {
    self.title = title
    self.count = count
    self.compact = compact
    self.actions = actions()
  }

  public var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 16) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text(title)
          .typeRole(compact ? .caption : .subhead)
          .foregroundStyle(compact ? theme.inkDim : theme.ink)
          .accessibilityAddTraits(.isHeader)
        if let count {
          Text(count)
            .font(.daily(size: 14).monospacedDigit())
            .foregroundStyle(theme.inkDim)
        }
      }
      Spacer(minLength: 0)
      actions
    }
  }
}

extension SectionHeader where Actions == EmptyView {
  public init(_ title: String, count: String? = nil, compact: Bool = false) {
    self.init(title, count: count, compact: compact) { EmptyView() }
  }
}

/// A visible key hint inside a button (`components/data/ShortcutKey.tsx`). Hidden from
/// VoiceOver so it never changes the button's name.
public struct ShortcutKey: View {
  private let key: String

  public init(_ key: String) {
    self.key = key
  }

  public var body: some View {
    Text(key)
      .font(.daily(size: 10))
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .overlay { Capsule().strokeBorder(.foreground.opacity(0.3)) }
      .opacity(0.7)
      .accessibilityHidden(true)
  }
}

// MARK: - Segmented pills

/// A rounded-full group of pills where one is on. Two looks from the web:
/// - `tabs`: panel tabs (`components/ui/legacy-tabs.tsx`), `role="tab"`, other content;
/// - `toggle`: the tasks "Lista / Quadro" switch (`components/tasks/segmented.ts`).
///
/// Like the web's tab list, only the active pill is in the Tab order and the arrow
/// keys move between pills, wrapping at the ends.
public struct SegmentedPills<ID: Hashable>: View {
  public struct Item: Identifiable {
    public var id: ID
    public var label: String
    /// Shown beside the label when above zero, as the web's `tab.count`.
    public var count: Int?

    public init(id: ID, label: String, count: Int? = nil) {
      self.id = id
      self.label = label
      self.count = count
    }
  }

  @FocusState private var focused: ID?
  @Binding private var selection: ID
  private let label: String
  private let items: [Item]
  private let style: SegmentedPillsStyle

  /// `label` names the whole group, as the web's `aria-label` on the tab list.
  public init(_ label: String, items: [Item], selection: Binding<ID>, style: SegmentedPillsStyle = .tabs) {
    self.label = label
    self.items = items
    _selection = selection
    self.style = style
  }

  public var body: some View {
    SegmentedGroup(style: style) {
      ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
        SegmentedPill(
          label: item.label,
          count: item.count,
          isSelected: item.id == selection,
          isFocused: focused == item.id,
          style: style
        ) {
          selection = item.id
        }
        .focusable(item.id == selection)
        .focused($focused, equals: item.id)
        .onKeyPress(.rightArrow) { move(from: offset, step: 1) }
        .onKeyPress(.leftArrow) { move(from: offset, step: -1) }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(label)
    .accessibilityAddTraits(.isTabBar)
  }

  private func move(from offset: Int, step: Int) -> KeyPress.Result {
    guard !items.isEmpty else { return .ignored }
    let target = items[SegmentedPillsStyle.index(from: offset, step: step, count: items.count)].id
    selection = target
    focused = target
    return .handled
  }
}

public enum SegmentedPillsStyle: String, Sendable, CaseIterable {
  /// `legacy-tabs.tsx`: `border bg-muted/70 p-[3px] gap-1 shadow-e1`; pills `h-8 px-3.5
  /// font-medium`, the active one `bg-glass-strong text-ink shadow-control`.
  case tabs
  /// `segmented.ts`: `border-line-strong bg-surface-2 p-0.5 gap-0.5 shadow-e1`; pills
  /// `h-7 px-2.5`, the active one `bg-brand-tint text-ink shadow-control`.
  case toggle

  public var pillHeight: CGFloat { self == .tabs ? 32 : 28 }
  public var pillPadding: CGFloat { self == .tabs ? 14 : 10 }
  public var groupInset: CGFloat { self == .tabs ? 3 : 2 }
  public var spacing: CGFloat { self == .tabs ? 4 : 2 }
  public var weight: Font.Weight { self == .tabs ? .medium : .regular }

  /// The group's surface. `--border` (the glass hairline) and `--muted` are not
  /// Theme tokens; line and line-soft stand in.
  public func groupPalette(theme: Theme) -> PillPalette {
    switch self {
    case .tabs:
      PillPalette(fill: theme.lineSoft.opacity(0.7), foreground: theme.inkMid, border: theme.line, shadow: .e1)
    case .toggle: PillPalette(fill: theme.surface2, foreground: theme.inkMid, border: theme.lineStrong, shadow: .e1)
    }
  }

  /// A pill's surface. `--glass-strong` is not a Theme token; surface-3 stands in
  /// until the glass surfaces land.
  public func pillPalette(isSelected: Bool, hovering: Bool, theme: Theme) -> PillPalette {
    guard isSelected else {
      return PillPalette(fill: .clear, foreground: hovering ? theme.ink : theme.inkMid)
    }
    let fill = self == .tabs ? theme.surface3 : theme.brandTint
    return PillPalette(fill: fill, foreground: theme.ink, shadow: .control)
  }

  /// The arrow-key target, wrapping at both ends (`legacy-tabs.tsx` `mover`).
  public static func index(from index: Int, step: Int, count: Int) -> Int {
    ((index + step) % count + count) % count
  }

  /// The accessible name of a pill: the web joins label and count with a comma so a
  /// screen reader pauses ("Entregues, 2", `legacy-tabs.tsx:53-56`).
  public static func accessibilityLabel(_ label: String, count: Int?) -> String {
    guard let count, count > 0 else { return label }
    return "\(label), \(count)"
  }
}

private struct SegmentedGroup<Content: View>: View {
  @Environment(\.theme) private var theme
  let style: SegmentedPillsStyle
  @ViewBuilder let content: Content

  var body: some View {
    HStack(spacing: style.spacing) { content }
      .padding(style.groupInset)
      .pillSurface(style.groupPalette(theme: theme), in: Capsule())
  }
}

private struct SegmentedPill: View {
  @Environment(\.theme) private var theme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hovering = false
  let label: String
  let count: Int?
  let isSelected: Bool
  let isFocused: Bool
  let style: SegmentedPillsStyle
  let select: () -> Void

  var body: some View {
    let palette = style.pillPalette(isSelected: isSelected, hovering: hovering, theme: theme)
    HStack(spacing: 6) {
      Text(label)
      if let count, count > 0 {
        Text("\(count)").monospacedDigit().foregroundStyle(theme.inkDim)
      }
    }
    .font(.daily(size: 14, weight: style.weight))
    .lineLimit(1)
    .foregroundStyle(palette.foreground)
    .padding(.horizontal, style.pillPadding)
    .frame(height: style.pillHeight)
    .pillSurface(palette, in: Capsule())
    .dailyFocusRing(isFocused, in: Capsule())
    .contentShape(.capsule)
    .focusEffectDisabled()
    .onHover { hovering = $0 }
    .onTapGesture(perform: select)
    .animation(Motion.ease(Motion.fast, reduceMotion: reduceMotion), value: isSelected)
    .accessibilityElement()
    .accessibilityLabel(SegmentedPillsStyle.accessibilityLabel(label, count: count))
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    .accessibilityAction(.default, select)
  }
}

// MARK: - Repo pill

/// A tracked repository (`components/PullsPanel.tsx:343-358`, GH-15): `rounded-full
/// border-line-strong bg-surface-2 py-0.5 pl-3 pr-1 text-sm text-ink-mid shadow-e1`,
/// with a `×` that turns danger on hover and is named `remover <repo>`.
public struct RepoPill: View {
  @Environment(\.theme) private var theme
  private let title: String
  private let onRemove: () -> Void

  public init(_ title: String, onRemove: @escaping () -> Void) {
    self.title = title
    self.onRemove = onRemove
  }

  public var body: some View {
    HStack(spacing: 4) {
      Text(title)
        .font(.daily(size: 14))
        .lineLimit(1)
      Button("×", action: onRemove)
        .buttonStyle(RemoveGlyphStyle())
        .focusEffectDisabled()
        .accessibilityLabel(Self.removeLabel(for: title))
        .help(Self.removeLabel(for: title))
    }
    .foregroundStyle(theme.inkMid)
    .padding(.leading, 12)
    .padding(.trailing, 4)
    .padding(.vertical, 2)
    .pillSurface(Self.palette(theme: theme), in: Capsule())
    .accessibilityElement(children: .contain)
  }

  /// The web's `aria-label`.
  public static func removeLabel(for repo: String) -> String { "remover \(repo)" }

  static func palette(theme: Theme) -> PillPalette {
    PillPalette(fill: theme.surface2, foreground: theme.inkMid, border: theme.lineStrong, shadow: .e1)
  }
}

/// `rounded-full p-1 leading-none text-ink-dim hover:text-danger` plus the focus ring.
private struct RemoveGlyphStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    RemoveGlyph(configuration: configuration)
  }
}

private struct RemoveGlyph: View {
  @Environment(\.theme) private var theme
  @Environment(\.isFocused) private var isFocused
  @State private var hovering = false
  let configuration: ButtonStyleConfiguration

  var body: some View {
    configuration.label
      .font(.daily(size: 14))
      .foregroundStyle(hovering ? theme.danger : theme.inkDim)
      .frame(width: 20, height: 20)
      .dailyFocusRing(isFocused, in: Circle())
      .contentShape(.circle)
      .onHover { hovering = $0 }
  }
}

// MARK: - Count slot

/// An unread count that always keeps its width (`components/email/FolderTree.tsx:
/// 219-229`, EM-24): with nothing to count it still lays out a transparent "0", so
/// the names beside it never shift. Lit, it is `rounded-full border-brand-edge
/// bg-brand-tint px-1.5 text-brand type-caption`. Hidden from VoiceOver like the
/// web's `aria-hidden`: the row's own name says the count.
public struct CountSlot: View {
  @Environment(\.theme) private var theme
  private let count: Int

  public init(_ count: Int) {
    self.count = count
  }

  public var body: some View {
    let lit = Self.isLit(count)
    Text(Self.text(for: count))
      .typeRole(.caption)
      .monospacedDigit()
      .foregroundStyle(lit ? theme.brand : .clear)
      .padding(.horizontal, 6)
      .background(lit ? theme.brandTint : .clear, in: .capsule)
      .overlay {
        if lit { Capsule().strokeBorder(theme.brandEdge) }
      }
      .accessibilityHidden(true)
  }

  public static func isLit(_ count: Int) -> Bool { count > 0 }

  /// The web renders "0" for an empty slot, transparent, so the width stays.
  public static func text(for count: Int) -> String { isLit(count) ? "\(count)" : "0" }
}

// MARK: - Shared control surface

/// The fill, text, rim and shadow of one pill-shaped control in one state. Kept as
/// data so the variant → token mapping is testable without rendering.
public struct PillPalette: Sendable, Equatable {
  public var fill: Color
  public var foreground: Color
  public var border: Color?
  public var shadow: ControlShadow

  public init(fill: Color, foreground: Color, border: Color? = nil, shadow: ControlShadow = .none) {
    self.fill = fill
    self.foreground = foreground
    self.border = border
    self.shadow = shadow
  }
}

/// The raised-control shadows of app/globals.css: `shadow-e1` and `shadow-e2`
/// (`--elevation-1/2`, :50-51, dark :310-311), `shadow-control` (`--control-rim`
/// plus e2, :840-844) and `shadow-button` (`--button-rim` plus e2, :834-838).
public enum ControlShadow: Sendable, Equatable {
  case none, e1, e2, control, button

  /// One drop shadow: CSS `0 y blur color` maps to radius = blur / 2.
  public struct Layer: Sendable, Equatable {
    public var opacity: Double
    public var radius: CGFloat
    public var y: CGFloat
  }

  /// The drop layers, without the inset `--shiny` sheen (too faint to draw at
  /// control size). Dark themes darken the drops (:310-311).
  public func layers(scheme: ColorScheme) -> [Layer] {
    let dark = scheme == .dark
    let contact = Layer(opacity: dark ? 0.35 : 0.05, radius: 0, y: 1)
    let lift = Layer(opacity: dark ? 0.30 : 0.05, radius: 1, y: 4)
    switch self {
    case .none: return []
    case .e1: return [contact]
    case .e2, .control, .button: return [contact, lift]
    }
  }

  /// The top inner highlight of `--control-rim` (:144, dark :304) and, roughly,
  /// of `--button-rim` (:139), whose brand-lightened rim has no relative-colour
  /// equivalent here; a white highlight reads the same at 1pt.
  public func rimOpacity(scheme: ColorScheme) -> Double {
    switch self {
    case .control: scheme == .dark ? 0.16 : 0.85
    case .button: 0.35
    case .none, .e1, .e2: 0
    }
  }
}

extension View {
  /// The keyboard focus ring of `lib/theme.ts` `focusRing` (:138): 3px of `--ring`
  /// (the brand) at 50%, offset by 1px.
  public func dailyFocusRing<S: InsettableShape>(_ visible: Bool, in shape: S) -> some View {
    modifier(FocusRingModifier(visible: visible, shape: shape))
  }

  // SURFACE HOOK (T013-3 → T013-2): every pill control (Chip, PillButton,
  // IconButton, SegmentedPills, RepoPill) paints its fill, rim and shadow through
  // this one modifier, so switching pills to `.glassSurface(.pill)` and the
  // Elevation tokens is a change here only.
  func pillSurface<S: InsettableShape>(_ palette: PillPalette, in shape: S) -> some View {
    modifier(PillSurfaceModifier(palette: palette, shape: shape))
  }
}

private struct FocusRingModifier<S: InsettableShape>: ViewModifier {
  @Environment(\.theme) private var theme
  let visible: Bool
  let shape: S

  func body(content: Content) -> some View {
    content.overlay {
      shape
        .strokeBorder(theme.brand.opacity(0.5), lineWidth: 3)
        .padding(-4)
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(false)
    }
  }
}

private struct PillSurfaceModifier<S: InsettableShape & Shape>: ViewModifier {
  let palette: PillPalette
  let shape: S

  // Raised pills (the web's shadow-control / shadow-button) become Liquid Glass
  // tinted with their fill (DP-5); flat ones (ghost, chips at rest) keep a plain
  // fill so they don't turn every row into glass.
  func body(content: Content) -> some View {
    content
      .background {
        if palette.shadow == .none {
          shape.fill(palette.fill)
        }
      }
      .glassEffect(palette.shadow == .none ? .identity : .regular.tint(palette.fill).interactive(), in: shape)
      .overlay {
        if let border = palette.border {
          shape.strokeBorder(border)
        }
      }
  }
}

/// One `ControlShadow.Layer`; no layer means the control has no drop at that depth.
private struct DropShadow: ViewModifier {
  let layer: ControlShadow.Layer?

  func body(content: Content) -> some View {
    if let layer {
      content.shadow(color: .black.opacity(layer.opacity), radius: layer.radius, y: layer.y)
    } else {
      content
    }
  }
}
