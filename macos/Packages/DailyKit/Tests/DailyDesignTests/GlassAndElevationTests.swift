import SwiftUI
import Testing

@testable import DailyDesign

/// Parses one CSS shadow literal as globals.css writes it, e.g.
/// `inset 0 30px 60px 0 oklch(1 0 0 / 6%)` or `0 1px 0 oklch(0 0 0 / 5%)`, so the
/// expectations below are the stylesheet text itself rather than restated numbers.
private func cssShadow(_ literal: String) -> ShadowLayer {
  var words = literal.split(separator: " ").map(String.init)
  let inset = words.first == "inset"
  if inset { words.removeFirst() }
  func length(_ word: String) -> CGFloat {
    let number = word.hasSuffix("px") ? String(word.dropLast(2)) : word
    guard let value = Double(number) else { Issue.record("not a length: \(word)"); return .nan }
    return CGFloat(value)
  }
  // oklch(L 0 0 / A%)
  let lightness = Double(words[words.count - 5].replacingOccurrences(of: "oklch(", with: ""))
  let alpha = Double(words[words.count - 1].replacingOccurrences(of: "%)", with: ""))
  guard let lightness, let alpha else {
    Issue.record("not an oklch colour: \(literal)")
    return ShadowLayer(y: .nan, blur: .nan, lightness: .nan, alpha: .nan)
  }
  return ShadowLayer(
    inset: inset, x: length(words[0]), y: length(words[1]), blur: length(words[2]),
    lightness: lightness, alpha: alpha / 100
  )
}

private let shinySmall = "inset 0 20px 50px 0 oklch(1 0 0 / 5%)"  // globals.css:46
private let shiny = "inset 0 30px 60px 0 oklch(1 0 0 / 6%)"  // globals.css:47
private let shinyLarge = "inset 0 50px 100px 0 oklch(1 0 0 / 7%)"  // globals.css:48

/// `--elevation-*` with `var(--shiny*)` expanded (globals.css:50-56 and :223-229).
private let cssElevations: [ColorScheme: [Elevation: [String]]] = [
  .light: [
    .e1: [shinySmall, "0 1px 0 oklch(0 0 0 / 5%)"],
    .e2: [shiny, "0 1px 0 oklch(0 0 0 / 5%)", "0 4px 2px oklch(0 0 0 / 5%)"],
    .e3: [shiny, "0 1px 0 oklch(0 0 0 / 5%)", "0 4px 2px oklch(0 0 0 / 5%)", "0 10px 5px oklch(0 0 0 / 10%)"],
    .e4: [shinyLarge, "0 2px 4px oklch(0 0 0 / 6%)", "0 12px 24px oklch(0 0 0 / 12%)"],
    .e5: [shinyLarge, "0 4px 8px oklch(0 0 0 / 8%)", "0 24px 48px oklch(0 0 0 / 18%)"],
  ],
  .dark: [
    .e1: [shinySmall, "0 1px 0 oklch(0 0 0 / 35%)"],
    .e2: [shiny, "0 1px 0 oklch(0 0 0 / 35%)", "0 4px 2px oklch(0 0 0 / 30%)"],
    .e3: [shiny, "0 1px 0 oklch(0 0 0 / 40%)", "0 4px 2px oklch(0 0 0 / 35%)", "0 10px 5px oklch(0 0 0 / 45%)"],
    .e4: [shinyLarge, "0 2px 4px oklch(0 0 0 / 45%)", "0 12px 24px oklch(0 0 0 / 55%)"],
    .e5: [shinyLarge, "0 4px 8px oklch(0 0 0 / 50%)", "0 24px 48px oklch(0 0 0 / 65%)"],
  ],
]

@Test(arguments: Elevation.allCases, [ColorScheme.light, .dark])
func elevationMatchesTheStylesheet(level: Elevation, scheme: ColorScheme) throws {
  let literals = try #require(cssElevations[scheme]?[level])
  let expected = literals.map(cssShadow)
  let actual = level.layers(for: scheme)
  #expect(actual.count == expected.count)
  for (got, want) in zip(actual, expected) {
    #expect(got.inset == want.inset)
    #expect(got.x == want.x)
    #expect(got.y == want.y)
    #expect(got.blur == want.blur)
    #expect(got.lightness == want.lightness)
    #expect(abs(got.alpha - want.alpha) < 1e-9)
  }
}

@Test func elevationBlurConvertsTheCSSRadiusToASigma() {
  #expect(ElevationModifier<Rectangle>.sigma(48) == 24)
  #expect(ElevationModifier<Rectangle>.reach(of: Elevation.e5.layers(for: .light)) == 150)
}

@Test func glassRoleShapes() {
  #expect(GlassRole.panel.shape() == GlassShape(.roundedRectangle(cornerRadius: 12)))
  #expect(GlassRole.bar.shape() == GlassShape(.roundedRectangle(cornerRadius: 16)))
  #expect(GlassRole.popover.shape() == GlassShape(.roundedRectangle(cornerRadius: 14)))
  #expect(GlassRole.pill.shape() == GlassShape(.capsule))
  #expect(GlassRole.panel.shape(cornerRadius: 17) == GlassShape(.roundedRectangle(cornerRadius: 17)))
  #expect(GlassRole.pill.shape(cornerRadius: 17) == GlassShape(.capsule))
}

@Test func glassRoleElevationAndInteraction() {
  #expect(GlassRole.panel.elevation == .e2)
  #expect(GlassRole.bar.elevation == .e2)
  #expect(GlassRole.popover.elevation == .e4)
  #expect(GlassRole.pill.elevation == .e1)
  #expect(GlassRole.allCases.filter(\.isInteractive) == [.pill])
}

@Test(arguments: GlassRole.allCases)
func glassRoleTintsWithTheThemeSurface(role: GlassRole) {
  let theme = Theme.resolve(scheme: .dark, backdrop: .catppuccin, density: .comfortable)
  let expected = role == .panel || role == .pill ? theme.surface2 : theme.surface3
  #expect(role.surface(in: theme) == expected)
  let glass = Glass.regular.tint(expected.opacity(role.tintOpacity)).interactive(role.isInteractive)
  #expect(role.glass(in: theme) == glass)
}
