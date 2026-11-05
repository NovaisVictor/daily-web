import DailyDesign
import SwiftUI

/// A menu behind a ghost icon button: the row's "⋯" (`PullRow.tsx`). A native menu
/// keeps the keyboard and VoiceOver behaviour of the web's dropdown; the circle takes
/// the icon button's tokens, since a menu draws its own control and ignores a custom
/// `ButtonStyle`.
struct PullIconMenu<Content: View>: View {
  @Environment(\.theme) private var theme
  @State private var hovering = false
  private let label: String
  private let systemImage: String
  private let content: Content

  init(_ label: String, systemImage: String, @ViewBuilder content: () -> Content) {
    self.label = label
    self.systemImage = systemImage
    self.content = content()
  }

  var body: some View {
    let size = IconButtonSize.small
    let palette = IconButtonStyle.palette(.ghost, highlighted: hovering, theme: theme)
    Menu {
      content
    } label: {
      Image(systemName: systemImage)
        .font(.system(size: size.glyphSize))
        .foregroundStyle(palette.foreground)
        .frame(width: size.side, height: size.side)
        .background(palette.fill, in: .circle)
        .overlay { Circle().strokeBorder(palette.border ?? .clear) }
        .contentShape(.circle)
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .fixedSize()
    .onHover { hovering = $0 }
    .help(label)
    .accessibilityLabel(label)
  }
}
