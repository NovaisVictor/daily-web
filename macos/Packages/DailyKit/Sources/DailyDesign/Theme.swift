import SwiftUI

// FROZEN INTERFACE (T006). Token names mirror the CSS custom properties in
// app/globals.css so a value can be traced back to the web. T103 fills in the
// real palettes in `Theme.resolve`; views read colors only through `Theme`.

/// The appearance choices the server stores (`lib/theme.ts:1-6`).
public enum ThemePreference: String, Sendable, CaseIterable, Codable { case system, light, dark }
public enum Backdrop: String, Sendable, CaseIterable, Codable { case mesh, catppuccin, dracula, wezterm }
public enum Density: String, Sendable, CaseIterable, Codable { case comfortable, compact }

/// Resolved colors and metrics for one scheme and backdrop.
public struct Theme: Sendable, Equatable {
  // Surfaces, from the page background up (`--surface-0` … `--surface-5`).
  public var surface0: Color
  public var surface1: Color
  public var surface2: Color
  public var surface3: Color
  // Text (`--ink`, `--ink-mid`, `--ink-dim`).
  public var ink: Color
  public var inkMid: Color
  public var inkDim: Color
  // Borders (`--line`, `--line-soft`, `--line-strong`).
  public var line: Color
  public var lineSoft: Color
  public var lineStrong: Color
  // Brand (`--brand`, `--brand-ink`, `--brand-tint`).
  public var brand: Color
  public var brandInk: Color
  public var brandTint: Color
  // Signals (`--signal-*` and their `-tint`).
  public var success: Color
  public var warning: Color
  public var danger: Color
  public var info: Color
  public var neutral: Color
  public var successTint: Color
  public var warningTint: Color
  public var dangerTint: Color
  public var infoTint: Color
  public var neutralTint: Color
  /// Board note papers (`--postit-*`), keyed by the server's `NotePaper` value.
  public var postit: [String: Color]
  public var postitInk: Color
  /// `--radius` (0.75rem = 12pt).
  public var radius: CGFloat
  public var density: Density

  public init(
    surface0: Color, surface1: Color, surface2: Color, surface3: Color,
    ink: Color, inkMid: Color, inkDim: Color,
    line: Color, lineSoft: Color, lineStrong: Color,
    brand: Color, brandInk: Color, brandTint: Color,
    success: Color, warning: Color, danger: Color, info: Color, neutral: Color,
    successTint: Color, warningTint: Color, dangerTint: Color, infoTint: Color, neutralTint: Color,
    postit: [String: Color], postitInk: Color,
    radius: CGFloat, density: Density
  ) {
    self.surface0 = surface0
    self.surface1 = surface1
    self.surface2 = surface2
    self.surface3 = surface3
    self.ink = ink
    self.inkMid = inkMid
    self.inkDim = inkDim
    self.line = line
    self.lineSoft = lineSoft
    self.lineStrong = lineStrong
    self.brand = brand
    self.brandInk = brandInk
    self.brandTint = brandTint
    self.success = success
    self.warning = warning
    self.danger = danger
    self.info = info
    self.neutral = neutral
    self.successTint = successTint
    self.warningTint = warningTint
    self.dangerTint = dangerTint
    self.infoTint = infoTint
    self.neutralTint = neutralTint
    self.postit = postit
    self.postitInk = postitInk
    self.radius = radius
    self.density = density
  }
}

extension EnvironmentValues {
  /// The active theme. The app sets it at the root from the stored appearance.
  @Entry public var theme: Theme = .fallback
}

extension Theme {
  /// Neutral system colors until T103 provides the palettes; also what previews
  /// get when nothing sets a theme.
  public static let fallback = Theme(
    surface0: Color(nsColor: .windowBackgroundColor),
    surface1: Color(nsColor: .controlBackgroundColor),
    surface2: Color(nsColor: .underPageBackgroundColor),
    surface3: Color(nsColor: .quaternaryLabelColor),
    ink: .primary, inkMid: .secondary, inkDim: Color(nsColor: .tertiaryLabelColor),
    line: Color(nsColor: .separatorColor), lineSoft: Color(nsColor: .separatorColor),
    lineStrong: Color(nsColor: .gridColor),
    brand: .green, brandInk: .white, brandTint: .green.opacity(0.15),
    success: .green, warning: .orange, danger: .red, info: .blue, neutral: .gray,
    successTint: .green.opacity(0.15), warningTint: .orange.opacity(0.15),
    dangerTint: .red.opacity(0.15), infoTint: .blue.opacity(0.15), neutralTint: .gray.opacity(0.15),
    postit: [:], postitInk: .black,
    radius: 12, density: .comfortable
  )

  /// Resolves the palette for a color scheme and backdrop. Dracula and WezTerm exist
  /// only in dark, so a light scheme with either resolves to the default light palette,
  /// as on the web. The page background itself comes from `BackdropPalette`.
  public static func resolve(scheme: ColorScheme, backdrop: Backdrop, density: Density) -> Theme {
    var theme = palette(scheme: scheme, backdrop: backdrop)
    theme.density = density
    return theme
  }
}
