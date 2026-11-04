import SwiftUI
import Testing

@testable import DailyDesign

/// Linear sRGB components of a resolved color, plus its opacity.
private struct Linear {
  var red: Double
  var green: Double
  var blue: Double
  var opacity: Double

  init(_ color: Color) {
    let resolved = color.resolve(in: EnvironmentValues())
    red = Double(resolved.linearRed)
    green = Double(resolved.linearGreen)
    blue = Double(resolved.linearBlue)
    opacity = Double(resolved.opacity)
  }

  init(red: Double, green: Double, blue: Double) {
    self.red = red
    self.green = green
    self.blue = blue
    opacity = 1
  }

  /// WCAG 2 relative luminance.
  var luminance: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }

  /// Paints `self` over an opaque `background`, blending in gamma space as browsers do.
  func over(_ background: Linear) -> Linear {
    func mix(_ top: Double, _ bottom: Double) -> Double {
      SRGB.decode(SRGB.encode(top) * opacity + SRGB.encode(bottom) * (1 - opacity))
    }
    return Linear(
      red: mix(red, background.red),
      green: mix(green, background.green),
      blue: mix(blue, background.blue)
    )
  }
}

private func contrast(_ foreground: Color, on background: Color) -> Double {
  let bottom = Linear(background)
  let top = Linear(foreground).over(bottom)
  let lighter = max(top.luminance, bottom.luminance)
  let darker = min(top.luminance, bottom.luminance)
  return (lighter + 0.05) / (darker + 0.05)
}

nonisolated private let combinations: [(ColorScheme, Backdrop)] = [ColorScheme.light, .dark].flatMap { scheme in
  Backdrop.allCases.map { (scheme, $0) }
}

@Suite struct OKLCHConversion {
  /// The hex values globals.css records beside its oklch literals.
  @Test(arguments: [
    (0.243, 0.03, 283.911, UInt32(0x1E1E2E)),  // --ctp-base
    (0.787, 0.119, 304.769, UInt32(0xCBA6F7)),  // --ctp-mauve
    (0.682, 0.206, 24.431, UInt32(0xFF5555)),  // --drc-red
    (0.871, 0.22, 148.025, UInt32(0x50FA7B)),  // --drc-green
    (0.158, 0.047, 302.755, UInt32(0x11071D)),  // --wzt-background
    (0.244, 0, 0, UInt32(0x202020)),  // --drc-background
  ])
  func matchesRecordedHex(lightness: Double, chroma: Double, hue: Double, hex: UInt32) {
    let converted = SRGB(oklch: lightness, chroma, hue)
    let expected = SRGB(hex: hex)
    // The CSS literals are rounded to three decimals, so allow about 1.5/255.
    #expect(abs(converted.red - expected.red) < 0.006)
    #expect(abs(converted.green - expected.green) < 0.006)
    #expect(abs(converted.blue - expected.blue) < 0.006)
  }

  @Test func whiteAndBlackAreExact() {
    let white = SRGB(oklch: 1, 0, 0)
    let black = SRGB(oklch: 0, 0, 0)
    #expect(abs(white.red - 1) < 1e-6 && abs(white.green - 1) < 1e-6 && abs(white.blue - 1) < 1e-6)
    #expect(abs(black.red) < 1e-9 && abs(black.green) < 1e-9 && abs(black.blue) < 1e-9)
  }

  @Test func keepsAlphaAndExtendedRange() {
    let ink = SRGB(oklch: 0.145, 0.01, 285, alpha: 0.72)
    #expect(ink.opacity == 0.72)
    // --brand oklch(0.5 0.128 155) sits just outside sRGB; it must not be clamped.
    #expect(SRGB(oklch: 0.5, 0.128, 155).red < 0)
  }

  @Test func transferFunctionRoundTrips() {
    for value in stride(from: -0.2, through: 1.2, by: 0.05) {
      #expect(abs(SRGB.decode(SRGB.encode(value)) - value) < 1e-9)
    }
  }
}

@Suite struct ThemeResolution {
  @Test func darkPalettesDifferPerBackdrop() {
    let themes = Backdrop.allCases.map { Theme.resolve(scheme: .dark, backdrop: $0, density: .comfortable) }
    for (index, theme) in themes.enumerated() {
      for other in themes[(index + 1)...] {
        #expect(theme != other)
      }
    }
  }

  @Test func lightDiffersFromDark() {
    #expect(
      Theme.resolve(scheme: .light, backdrop: .mesh, density: .comfortable)
        != Theme.resolve(scheme: .dark, backdrop: .mesh, density: .comfortable)
    )
  }

  /// The web has no light Dracula, WezTerm or Catppuccin palette: only the page
  /// background changes for Catppuccin, which `BackdropPalette` carries.
  @Test(arguments: [Backdrop.catppuccin, .dracula, .wezterm])
  func lightFallsBackToDefault(backdrop: Backdrop) {
    #expect(
      Theme.resolve(scheme: .light, backdrop: backdrop, density: .comfortable)
        == Theme.resolve(scheme: .light, backdrop: .mesh, density: .comfortable)
    )
  }

  @Test func weztermChangesOnlyTheFloor() {
    var wezterm = Theme.resolve(scheme: .dark, backdrop: .wezterm, density: .comfortable)
    let dark = Theme.resolve(scheme: .dark, backdrop: .mesh, density: .comfortable)
    #expect(wezterm.surface0 != dark.surface0)
    #expect(wezterm.surface1 != dark.surface1)
    wezterm.surface0 = dark.surface0
    wezterm.surface1 = dark.surface1
    #expect(wezterm == dark)
  }

  @Test func densityIsCarried() {
    let theme = Theme.resolve(scheme: .light, backdrop: .mesh, density: .compact)
    #expect(theme.density == .compact)
    #expect(theme.metrics == .compact)
    #expect(DensityMetrics.compact.rowVerticalPadding < DensityMetrics.comfortable.rowVerticalPadding)
  }

  @Test(arguments: combinations)
  func everyPaperIsPresent(scheme: ColorScheme, backdrop: Backdrop) {
    let theme = Theme.resolve(scheme: scheme, backdrop: backdrop, density: .comfortable)
    #expect(Set(theme.postit.keys) == Set(PostitPaper.allCases.map(\.rawValue)))
  }

  @Test func backdropsMatchTheWeb() {
    #expect(BackdropPalette.resolve(scheme: .light, backdrop: .mesh).blobs.count == 5)
    #expect(BackdropPalette.resolve(scheme: .light, backdrop: .catppuccin).isFlat)
    #expect(
      BackdropPalette.resolve(scheme: .light, backdrop: .catppuccin)
        != BackdropPalette.resolve(scheme: .light, backdrop: .mesh)
    )
    #expect(
      BackdropPalette.resolve(scheme: .light, backdrop: .dracula)
        == BackdropPalette.resolve(scheme: .light, backdrop: .mesh)
    )
    #expect(
      BackdropPalette.resolve(scheme: .light, backdrop: .wezterm)
        == BackdropPalette.resolve(scheme: .light, backdrop: .mesh)
    )
    #expect(BackdropPalette.resolve(scheme: .dark, backdrop: .catppuccin).isFlat)
    #expect(BackdropPalette.resolve(scheme: .dark, backdrop: .dracula).isFlat)
    #expect(BackdropPalette.resolve(scheme: .dark, backdrop: .wezterm).blobs.count == 5)
    #expect(
      BackdropPalette.resolve(scheme: .dark, backdrop: .wezterm)
        != BackdropPalette.resolve(scheme: .dark, backdrop: .mesh)
    )
  }
}

@Suite struct Contrast {
  @Test(arguments: combinations)
  func inkIsAAOnPageAndPanel(scheme: ColorScheme, backdrop: Backdrop) {
    let theme = Theme.resolve(scheme: scheme, backdrop: backdrop, density: .comfortable)
    #expect(contrast(theme.ink, on: theme.surface0) >= 4.5)
    #expect(contrast(theme.ink, on: theme.surface1) >= 4.5)
  }

  @Test(arguments: combinations)
  func inkMidReadsOnThePage(scheme: ColorScheme, backdrop: Backdrop) {
    let theme = Theme.resolve(scheme: scheme, backdrop: backdrop, density: .comfortable)
    #expect(contrast(theme.inkMid, on: theme.surface0) >= 3)
  }

  /// globals.css:104-107 promises at least 4.5:1 for every ink/paper pair.
  @Test(arguments: combinations)
  func postitInkIsAAOnEveryPaper(scheme: ColorScheme, backdrop: Backdrop) {
    let theme = Theme.resolve(scheme: scheme, backdrop: backdrop, density: .comfortable)
    for (paper, color) in theme.postit {
      #expect(contrast(theme.postitInk, on: color) >= 4.5, "paper \(paper)")
    }
  }

  @Test func contrastHelperMatchesKnownPair() {
    #expect(abs(contrast(.black, on: .white) - 21) < 0.01)
  }
}

@Suite struct Components {
  @Test(arguments: [
    ("Ana Souza", "AS"),
    ("Maria da Silva Lima", "ML"),
    ("victor", "V"),
    ("  ", ""),
  ])
  func avatarInitials(name: String, expected: String) {
    #expect(Avatar.initials(for: name) == expected)
  }

  @Test func typeScaleMatchesTheWeb() {
    #expect(TypeRole.display.size == 44)
    #expect(TypeRole.caption.size == 13)
    #expect(TypeRole.allCases.count == 7)
    #expect(TypeRole.title.tracking == 34 * -0.04)
  }

  @Test func toastsCompareByContent() {
    let id = UUID()
    #expect(ToastMessage(id: id, kind: .info, text: "a") == ToastMessage(id: id, kind: .info, text: "a"))
    #expect(ToastMessage(id: id, kind: .info, text: "a") != ToastMessage(id: id, kind: .error, text: "a"))
  }
}
