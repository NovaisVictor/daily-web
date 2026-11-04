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

/// A filter toggle (`components/ui/Chip.tsx`). Lit uses the brand tint with a neutral
/// rim: a chip that is on is a control, not an action.
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
    Text(title)
      .font(.system(size: 14))
      .lineLimit(1)
      .foregroundStyle(isOn ? theme.ink : (hovering ? theme.ink : theme.inkMid))
      .padding(.horizontal, 14)
      .frame(height: theme.metrics.controlHeight)
      .background(background, in: .capsule)
      .overlay { Capsule().strokeBorder(isOn ? theme.brandEdge : theme.lineStrong) }
      .overlay {
        // The web focus ring: 3px of `--ring` at 50%, offset by 1px.
        Capsule()
          .strokeBorder(theme.brand.opacity(0.5), lineWidth: 3)
          .padding(-4)
          .opacity(focused ? 1 : 0)
      }
      .contentShape(.capsule)
      .opacity(isDisabled ? 0.5 : 1)
      .animation(Motion.ease(Motion.fast, reduceMotion: reduceMotion), value: isOn)
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

  private var background: Color {
    if isOn { return theme.brandTint }
    // `hover:bg-accent`; `--accent` is not a Theme token, line-soft is its neighbour.
    return hovering ? theme.lineSoft : theme.surface2
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
        .font(.system(size: 14))
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
          .font(.system(size: size * 0.4, weight: .medium))
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
            .font(.system(size: 14).monospacedDigit())
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
      .font(.system(size: 10))
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .overlay { Capsule().strokeBorder(.foreground.opacity(0.3)) }
      .opacity(0.7)
      .accessibilityHidden(true)
  }
}
