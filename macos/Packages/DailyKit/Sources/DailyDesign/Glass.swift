import SwiftUI

// The web's `.glass` / `.glass-strong` (globals.css:919-928) is a CSS backdrop blur.
// The native app replaces it with macOS 26 Liquid Glass (spec 013, DP-5): a
// deliberate divergence that follows the platform instead of imitating the blur.

/// The outline of a glass surface: a rounded rectangle for containers, a capsule
/// for controls (`--radius` is for containers only, globals.css:130-132).
public struct GlassShape: Shape, Equatable {
  public enum Kind: Sendable, Equatable {
    case roundedRectangle(cornerRadius: CGFloat)
    case capsule
  }

  public var kind: Kind

  public init(_ kind: Kind) {
    self.kind = kind
  }

  public func path(in rect: CGRect) -> Path {
    switch kind {
    case .roundedRectangle(let cornerRadius): RoundedRectangle(cornerRadius: cornerRadius).path(in: rect)
    case .capsule: Capsule().path(in: rect)
    }
  }
}

/// What a glass surface is for. Each role carries the shape, the elevation and the
/// tint of the web component it replaces.
public enum GlassRole: String, Sendable, CaseIterable {
  /// A Home panel or card (`cardSurface`, components/data/Panel.tsx:6-7).
  case panel
  /// A toolbar or header bar (components/shell/Header.tsx:63, AppShell.tsx:80).
  case bar
  /// A menu, the notifications bell, the palette (components/ui/popover.tsx:32,
  /// dropdown-menu.tsx:44, NotificationsBell.tsx:248).
  case popover
  /// A capsule control: buttons, chips, segmented pills (components/ui/button.tsx:7).
  case pill

  /// The default corner radius, or `nil` for the capsule.
  public var cornerRadius: CGFloat? {
    switch self {
    // `--radius`, 0.75rem: spec 013 FR-013-02 sets the panels on it. The web's
    // cardSurface says `rounded-xl` (17px); the spec chose the base radius.
    case .panel: Radius.medium
    // `rounded-2xl`, Tailwind's 1rem (Header.tsx:63).
    case .bar: 16
    // `rounded-lg`, `--radius-lg` (popover.tsx:32, NotificationsBell.tsx:248).
    case .popover: Radius.large
    case .pill: nil
    }
  }

  /// The shape, with `cornerRadius` replacing the role's default for a rounded role.
  /// A pill stays a capsule whatever the radius.
  public func shape(cornerRadius: CGFloat? = nil) -> GlassShape {
    guard let radius = self.cornerRadius else { return GlassShape(.capsule) }
    return GlassShape(.roundedRectangle(cornerRadius: cornerRadius ?? radius))
  }

  /// The elevation the web gives the same surface.
  public var elevation: Elevation {
    switch self {
    case .panel: .e2  // Panel.tsx:7 `shadow-e2`
    case .bar: .e2  // AppShell.tsx:80 `shadow-e2`
    case .popover: .e4  // popover.tsx:32, dropdown-menu.tsx:44 `shadow-e4`
    case .pill: .e1  // button.tsx:7 `shadow-e1`
    }
  }

  /// Controls react to the pointer; containers do not.
  public var isInteractive: Bool { self == .pill }

  /// How strongly the theme surface tints the glass. Light enough that the glass
  /// still reads as glass, strong enough that each backdrop keeps its colour.
  /// Menus are the most opaque, as `--popover` is on the web (94%, globals.css:156).
  public var tintOpacity: Double {
    switch self {
    case .panel, .bar: 0.5
    case .popover: 0.7
    case .pill: 0.4
    }
  }

  /// The theme surface this role sits on (`--surface-*`, globals.css:36-41).
  /// The popover's own `--surface-4` is not in `Theme`; `surface3` is the same
  /// white in light and 0.02 darker in dark.
  public func surface(in theme: Theme) -> Color {
    switch self {
    case .panel, .pill: theme.surface2
    case .bar, .popover: theme.surface3
    }
  }

  /// The Liquid Glass material for this role in `theme`.
  public func glass(in theme: Theme) -> Glass {
    Glass.regular
      .tint(surface(in: theme).opacity(tintOpacity))
      .interactive(isInteractive)
  }
}

/// Puts a view on a Liquid Glass surface of a role, tinted with the active theme
/// and carrying the web elevation of the same component.
public struct GlassSurface: ViewModifier {
  @Environment(\.theme) private var theme
  private let role: GlassRole
  private let cornerRadius: CGFloat?
  private let elevationOverride: Elevation?

  public init(_ role: GlassRole = .panel, cornerRadius: CGFloat? = nil, elevation: Elevation? = nil) {
    self.role = role
    self.cornerRadius = cornerRadius
    self.elevationOverride = elevation
  }

  public func body(content: Content) -> some View {
    let shape = role.shape(cornerRadius: cornerRadius)
    // Elevation first: its inset glow then sits on the glass, under the content,
    // and its drop shadows fall outside the shape, beside the glass.
    content
      .elevation(elevationOverride ?? role.elevation, in: shape)
      .glassEffect(role.glass(in: theme), in: shape)
  }
}

extension View {
  /// Liquid Glass for `role`. `cornerRadius` overrides the role's radius (ignored
  /// for a pill); `elevation` overrides the role's shadow where the web component
  /// uses another one, such as a dialog's `shadow-e5`.
  public func glassSurface(
    _ role: GlassRole = .panel,
    cornerRadius: CGFloat? = nil,
    elevation: Elevation? = nil
  ) -> some View {
    modifier(GlassSurface(role, cornerRadius: cornerRadius, elevation: elevation))
  }
}

/// Groups nearby glass surfaces (panel header controls, a row of pills) so they
/// render as one Liquid Glass layer and blend into each other when close, as
/// `GlassEffectContainer` does. `spacing` is the distance at which they merge.
public struct GlassGroup<Content: View>: View {
  private let spacing: CGFloat?
  private let content: Content

  public init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
    self.spacing = spacing
    self.content = content()
  }

  public var body: some View {
    GlassEffectContainer(spacing: spacing) { content }
  }
}
