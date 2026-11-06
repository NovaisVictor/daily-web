import SwiftUI

// MARK: - Icon menu

/// A menu behind an icon button: a row's "⋯" (`PullRow.tsx`) or the Jira sort circle
/// (`JiraPanel.tsx:840-864`, JR-14). A native menu keeps the keyboard and VoiceOver
/// behaviour of the web's dropdown; the circle takes the icon button's tokens, since a
/// menu draws its own control and ignores a custom `ButtonStyle`.
public struct IconMenu<Content: View>: View {
  @Environment(\.theme) private var theme
  @State private var hovering = false
  private let label: String
  private let systemImage: String
  private let size: IconButtonSize
  private let variant: IconButtonVariant
  private let content: Content

  public init(
    _ label: String,
    systemImage: String,
    size: IconButtonSize = .regular,
    variant: IconButtonVariant = .ghost,
    @ViewBuilder content: () -> Content
  ) {
    self.label = label
    self.systemImage = systemImage
    self.size = size
    self.variant = variant
    self.content = content()
  }

  public var body: some View {
    let palette = IconButtonStyle.palette(variant, highlighted: hovering, theme: theme)
    Menu {
      content
    } label: {
      raised(
        Image(systemName: systemImage)
          .font(.system(size: size.glyphSize))
          .foregroundStyle(palette.foreground)
          .frame(width: size.side, height: size.side)
          .background(palette.fill, in: .circle)
          .overlay { Circle().strokeBorder(palette.border ?? .clear) },
        shadow: palette.shadow
      )
      .contentShape(.circle)
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .fixedSize()
    .onHover { hovering = $0 }
    // `transition-colors duration-100`, as `IconButtonStyle`.
    .dailyAnimation(Motion.hover, value: hovering)
    .help(label)
    .accessibilityLabel(label)
  }

  /// Raised variants (`shadow-e1`) lift off the row; the flat ones sit on it.
  @ViewBuilder
  private func raised(_ view: some View, shadow: ControlShadow) -> some View {
    if shadow == .none {
      view
    } else {
      view.elevation(.e1, in: Circle())
    }
  }
}

// MARK: - Pill select

/// The web's native `<select>` dressed as a pill (`selectClass`, lib/theme.ts:143:
/// `h-8 rounded-full border bg-glass px-3 text-sm shadow-e1`): the chosen option and
/// a chevron, opening a menu that checks the current one.
public struct PillSelect<Value: Hashable>: View {
  private let label: String
  @Binding private var selection: Value
  private let options: [Value]
  private let title: (Value) -> String

  public init(label: String, selection: Binding<Value>, options: [Value], title: @escaping (Value) -> String) {
    self.label = label
    _selection = selection
    self.options = options
    self.title = title
  }

  public var body: some View {
    Menu {
      Picker(label, selection: $selection) {
        ForEach(options, id: \.self) { Text(title($0)).tag($0) }
      }
      .pickerStyle(.inline)
      .labelsHidden()
    } label: {
      HStack(spacing: 6) {
        Text(title(selection))
        // SF Symbol sizing only: the chevron of the browser select.
        Image(systemName: "chevron.down")
          .font(.system(size: 10, weight: .semibold))
          .accessibilityHidden(true)
      }
    }
    .menuStyle(.button)
    .menuIndicator(.hidden)
    .pillButtonStyle(.outline, size: .small)
    .fixedSize()
    .accessibilityLabel(label)
    .accessibilityValue(title(selection))
  }
}
