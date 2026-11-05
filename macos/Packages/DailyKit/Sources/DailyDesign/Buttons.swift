import SwiftUI

// MARK: - Pill button

/// The variants of `components/ui/button.tsx` that the app uses. `secondary` has no
/// native call site, so it is not reproduced; `link` is `LinkButtonStyle`, since it
/// keeps none of the pill's height, padding or font.
public enum PillButtonVariant: String, Sendable, CaseIterable {
  /// `default` / `glow`: the brand face (`--button-face`, globals.css:134) with `shadow-button`.
  case primary
  /// `border-line-strong bg-surface-2 hover:bg-accent` with the press shadows.
  case outline
  /// `hover:bg-accent`, nothing at rest.
  case ghost
  /// `bg-destructive text-white hover:bg-destructive/90 dark:bg-destructive/60`.
  case destructive
}

/// The text sizes of `button.tsx` (`size: default | sm`).
public enum PillButtonSize: String, Sendable, CaseIterable {
  /// `sm`: `h-8 gap-1.5 px-3.5`.
  case small
  /// `default`: `h-9 gap-2 px-5`.
  case medium

  public var height: CGFloat {
    switch self {
    case .small: 32
    case .medium: 36
    }
  }

  public var horizontalPadding: CGFloat {
    switch self {
    case .small: 14
    case .medium: 20
    }
  }

  /// The gap between the glyph and the title.
  public var spacing: CGFloat {
    switch self {
    case .small: 6
    case .medium: 8
    }
  }
}

/// A rounded-full text button with the web's variants and sizes
/// (`components/ui/button.tsx`). Apply it with `View.pillButtonStyle(_:size:glow:)`,
/// which also hides the system focus effect in favour of the web ring.
public struct PillButtonStyle: ButtonStyle {
  public var variant: PillButtonVariant
  public var size: PillButtonSize
  /// `variant="glow"`: the primary face plus `hover:shadow-glow`. The web spends it on
  /// the one action of a screen, the login "Entrar" (`app/login/page.tsx:83-86`).
  public var glow: Bool

  public init(_ variant: PillButtonVariant = .primary, size: PillButtonSize = .medium, glow: Bool = false) {
    self.variant = variant
    self.size = size
    self.glow = glow
  }

  public func makeBody(configuration: Configuration) -> some View {
    PillButtonBody(configuration: configuration, style: self)
  }

  /// The colours and shadow of a variant at rest or under the pointer. `--accent`
  /// is not a Theme token; line-soft is its neighbour in every palette and stands in.
  public static func palette(
    _ variant: PillButtonVariant,
    hovering: Bool,
    theme: Theme,
    scheme: ColorScheme
  ) -> PillPalette {
    switch variant {
    case .primary:
      // Hover is `brightness-[1.06]` on the face, applied by the body, not a new fill.
      return PillPalette(fill: theme.brand, foreground: theme.brandInk, shadow: .button)
    case .outline:
      return PillPalette(
        fill: hovering ? theme.lineSoft : theme.surface2,
        foreground: theme.ink,
        border: theme.lineStrong,
        shadow: hovering ? .e2 : .e1
      )
    case .ghost:
      // `dark:hover:bg-accent/50`.
      let hover = scheme == .dark ? theme.lineSoft.opacity(0.5) : theme.lineSoft
      return PillPalette(fill: hovering ? hover : .clear, foreground: theme.ink)
    case .destructive:
      // `text-white`; dark mutes the fill to 60% (`dark:bg-destructive/60`).
      let fill = scheme == .dark ? theme.danger.opacity(0.6) : theme.danger.opacity(hovering ? 0.9 : 1)
      return PillPalette(fill: fill, foreground: .white, shadow: hovering ? .e2 : .e1)
    }
  }

  /// `active:` drops the press shadow (`active:shadow-none`) and the face settles to e1.
  public static func pressedShadow(_ variant: PillButtonVariant) -> ControlShadow {
    variant == .primary ? .e1 : .none
  }
}

private struct PillButtonBody: View {
  @Environment(\.theme) private var theme
  @Environment(\.colorScheme) private var scheme
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.isFocused) private var isFocused
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hovering = false
  let configuration: ButtonStyleConfiguration
  let style: PillButtonStyle

  var body: some View {
    let pressed = configuration.isPressed
    var palette = PillButtonStyle.palette(style.variant, hovering: hovering, theme: theme, scheme: scheme)
    if pressed { palette.shadow = PillButtonStyle.pressedShadow(style.variant) }
    // `disabled:shadow-none`.
    if !isEnabled { palette.shadow = .none }
    let isPrimary = style.variant == .primary

    return configuration.label
      .labelStyle(PillLabelStyle(spacing: style.size.spacing))
      .font(.daily(size: 14, weight: .medium))
      .lineLimit(1)
      .foregroundStyle(palette.foreground)
      .padding(.horizontal, style.size.horizontalPadding)
      .frame(height: style.size.height)
      .background {
        if isPrimary { ButtonFace(shape: Capsule()) }
      }
      .pillSurface(palette, in: Capsule())
      .modifier(GlowShadow(visible: style.glow && isPrimary && hovering && !pressed))
      // CSS `brightness()` multiplies; SwiftUI's adds. ±0.04 matches 1.06 and 0.95 on
      // the mid-lightness brand.
      .brightness(isPrimary ? (pressed ? -0.04 : (hovering ? 0.04 : 0)) : 0)
      // `motion-safe:active:translate-y-px`.
      .offset(y: pressed && !reduceMotion && style.variant != .ghost ? 1 : 0)
      .dailyFocusRing(isFocused, in: Capsule())
      .opacity(isEnabled ? 1 : 0.5)
      .contentShape(.capsule)
      .onHover { hovering = $0 && isEnabled }
      // `transition-all duration-150 ease-brand`.
      .animation(Motion.ease(0.150, reduceMotion: reduceMotion), value: hovering)
      .animation(Motion.ease(0.150, reduceMotion: reduceMotion), value: pressed)
  }
}

/// The 145° sheen of `--button-face` (globals.css:134-138): the brand lifted by
/// +0.055 L at the top left and dropped by −0.05 L at the bottom right. Relative
/// OKLCH colours have no SwiftUI form, so a white-to-black wash over the brand fill
/// stands in for the two stops.
private struct ButtonFace<FaceShape: Shape>: View {
  var shape: FaceShape

  var body: some View {
    shape
      .fill(
        LinearGradient(
          colors: [.white.opacity(0.12), .black.opacity(0.10)],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
  }
}

/// `shadow-glow` (`--glow`, globals.css:57): `0 0 8px` white at 35% and `0 0 16px` at 20%.
private struct GlowShadow: ViewModifier {
  let visible: Bool

  func body(content: Content) -> some View {
    content
      .shadow(color: .white.opacity(visible ? 0.35 : 0), radius: 4)
      .shadow(color: .white.opacity(visible ? 0.20 : 0), radius: 8)
  }
}

/// Glyph and title side by side with the size's gap (`gap-1.5` / `gap-2`).
private struct PillLabelStyle: LabelStyle {
  let spacing: CGFloat

  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: spacing) {
      configuration.icon
      configuration.title
    }
  }
}

// MARK: - Icon button

/// The square sizes of the web's glyph-only buttons.
public enum IconButtonSize: String, Sendable, CaseIterable {
  /// `icon-xs`, `size-6` (button.tsx), glyph `size-3`.
  case extraSmall
  /// `size-7`, the email row actions (`EmailPanel.tsx:1934`, EM-8).
  case small
  /// `size-8`, the Jira sort button (`JiraPanel.tsx:845`, JR-14) and `icon-sm` (button.tsx).
  case regular

  public var side: CGFloat {
    switch self {
    case .extraSmall: 24
    case .small: 28
    case .regular: 32
    }
  }

  /// Point size of the SF Symbol, chosen so its box matches the web's `size-3` / `size-4` svg.
  public var glyphSize: CGFloat {
    switch self {
    case .extraSmall: 11
    case .small, .regular: 14
    }
  }
}

public enum IconButtonVariant: String, Sendable, CaseIterable {
  /// No rim at rest; `hover:border-line hover:bg-surface-3 hover:text-ink`, kept while
  /// open (`aria-expanded:`). The email row actions (`EmailPanel.tsx:1934`) and the
  /// ghost `IconAction` (`components/data/IconAction.tsx`).
  case ghost
  /// Always rimmed and raised: `border-line-strong bg-surface-2 text-ink-mid shadow-e1
  /// hover:bg-accent`, the Jira sort circle (`JiraPanel.tsx:840-848`).
  case outline
  /// The brand face of `variant="default"`: the pomodoro play/pause
  /// (`IconAction variant="default"`, `components/Pomodoro.tsx:107-117`).
  case primary
  /// The ghost circle whose glyph and rim turn danger under the pointer
  /// (`hover:border-danger/40 hover:text-danger`, `EmailPanel.tsx:1499-1501`): the
  /// trash buttons.
  case destructive
}

/// A circular glyph-only button. Prefer `IconButton`, which also sets the accessible
/// name and the tooltip the web's `IconAction` requires.
public struct IconButtonStyle: ButtonStyle {
  public var size: IconButtonSize
  public var variant: IconButtonVariant
  /// The web's `aria-expanded`: the menu or popover it opens is showing.
  public var isActive: Bool

  public init(size: IconButtonSize = .regular, variant: IconButtonVariant = .ghost, isActive: Bool = false) {
    self.size = size
    self.variant = variant
    self.isActive = isActive
  }

  public func makeBody(configuration: Configuration) -> some View {
    IconButtonBody(configuration: configuration, style: self)
  }

  /// `--accent` stands in as line-soft, as in `PillButtonStyle`.
  public static func palette(_ variant: IconButtonVariant, highlighted: Bool, theme: Theme) -> PillPalette {
    switch variant {
    case .ghost:
      return highlighted
        ? PillPalette(fill: theme.surface3, foreground: theme.ink, border: theme.line)
        : PillPalette(fill: .clear, foreground: theme.inkDim, border: .clear)
    case .outline:
      return PillPalette(
        fill: highlighted ? theme.lineSoft : theme.surface2,
        foreground: highlighted ? theme.ink : theme.inkMid,
        border: theme.lineStrong,
        shadow: .e1
      )
    case .primary:
      // Hover is `brightness-[1.06]` on the face, applied by the body, as in `PillButtonStyle`.
      return PillPalette(fill: theme.brand, foreground: theme.brandInk, shadow: .button)
    case .destructive:
      return highlighted
        ? PillPalette(fill: theme.surface3, foreground: theme.danger, border: theme.danger.opacity(0.4))
        : PillPalette(fill: .clear, foreground: theme.inkDim, border: .clear)
    }
  }
}

private struct IconButtonBody: View {
  @Environment(\.theme) private var theme
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.isFocused) private var isFocused
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hovering = false
  let configuration: ButtonStyleConfiguration
  let style: IconButtonStyle

  var body: some View {
    let palette = IconButtonStyle.palette(
      style.variant,
      highlighted: hovering || style.isActive || configuration.isPressed,
      theme: theme
    )
    let isPrimary = style.variant == .primary
    return configuration.label
      .labelStyle(.iconOnly)
      .font(.system(size: style.size.glyphSize))
      .foregroundStyle(palette.foreground)
      .frame(width: style.size.side, height: style.size.side)
      .background {
        if isPrimary { ButtonFace(shape: Circle()) }
      }
      .pillSurface(palette, in: Circle())
      .brightness(isPrimary ? (configuration.isPressed ? -0.04 : (hovering ? 0.04 : 0)) : 0)
      .dailyFocusRing(isFocused, in: Circle())
      .opacity(isEnabled ? 1 : 0.5)
      .contentShape(.circle)
      .onHover { hovering = $0 && isEnabled }
      // `transition-colors duration-100`.
      .animation(Motion.ease(Motion.fast, reduceMotion: reduceMotion), value: hovering)
  }
}

/// A glyph-only button that keeps its words (`components/data/IconAction.tsx`): the
/// label is the accessible name and the tooltip, as the web's `aria-label` and
/// `TooltipContent`.
public struct IconButton: View {
  private let label: String
  private let systemImage: String
  private let style: IconButtonStyle
  private let action: () -> Void

  public init(
    _ label: String,
    systemImage: String,
    size: IconButtonSize = .regular,
    variant: IconButtonVariant = .ghost,
    isActive: Bool = false,
    action: @escaping () -> Void
  ) {
    self.label = label
    self.systemImage = systemImage
    style = IconButtonStyle(size: size, variant: variant, isActive: isActive)
    self.action = action
  }

  public var body: some View {
    Button(action: action) {
      Image(systemName: systemImage).accessibilityHidden(true)
    }
    .buttonStyle(style)
    .focusEffectDisabled()
    .help(label)
    .accessibilityLabel(label)
  }
}

// MARK: - Link button

/// `variant="link"` of `components/ui/button.tsx`: `text-primary underline-offset-4
/// hover:underline`. Unlike the pills it keeps the surrounding font and line, since the
/// web uses it inside sentences ("comentário publicado · abrir no Jira") and as the
/// "tentar de novo" after an error. Apply it with `View.linkButtonStyle()`.
public struct LinkButtonStyle: ButtonStyle {
  public init() {}

  public func makeBody(configuration: Configuration) -> some View {
    LinkButtonBody(configuration: configuration)
  }
}

private struct LinkButtonBody: View {
  @Environment(\.theme) private var theme
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.isFocused) private var isFocused
  @State private var hovering = false
  let configuration: ButtonStyleConfiguration

  var body: some View {
    configuration.label
      .foregroundStyle(theme.brand)
      .underline(hovering || isFocused)
      .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.5)
      .contentShape(.rect)
      .onHover { hovering = $0 && isEnabled }
  }
}

extension View {
  /// Applies `PillButtonStyle` and replaces the system focus effect with the web ring.
  public func pillButtonStyle(
    _ variant: PillButtonVariant = .primary,
    size: PillButtonSize = .medium,
    glow: Bool = false
  ) -> some View {
    buttonStyle(PillButtonStyle(variant, size: size, glow: glow)).focusEffectDisabled()
  }

  /// Applies `LinkButtonStyle`; the focused link shows its underline in place of the
  /// system focus effect.
  public func linkButtonStyle() -> some View {
    buttonStyle(LinkButtonStyle()).focusEffectDisabled()
  }

  /// Applies `IconButtonStyle` and replaces the system focus effect with the web ring.
  /// The caller still owes an `accessibilityLabel` and `help`; `IconButton` sets both.
  public func iconButtonStyle(
    size: IconButtonSize = .regular,
    variant: IconButtonVariant = .ghost,
    isActive: Bool = false
  ) -> some View {
    buttonStyle(IconButtonStyle(size: size, variant: variant, isActive: isActive)).focusEffectDisabled()
  }
}
