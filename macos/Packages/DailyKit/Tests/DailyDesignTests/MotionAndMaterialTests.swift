import SwiftUI
import Testing

@testable import DailyDesign

@Suite struct RadiusTokens {
  @Test func nestedIsConcentric() {
    #expect(Radius.nested(Radius.extraLarge, inset: 4) == 13)
    #expect(Radius.nested(Radius.medium, inset: 0) == Radius.medium)
  }

  @Test func nestedNeverGoesBelowTiny() {
    #expect(Radius.nested(Radius.medium, inset: 10) == Radius.tiny)
    #expect(Radius.nested(Radius.small, inset: 40) == Radius.tiny)
  }
}

@Suite struct MotionTokens {
  @Test func reduceMotionDropsTheAnimation() {
    #expect(Motion.ease(reduceMotion: true) == nil)
    #expect(Motion.ease(Motion.hover, reduceMotion: true) == nil)
    #expect(Motion.ease(Motion.control, reduceMotion: false) == Motion.ease(Motion.control))
  }

  @Test(arguments: [true, false])
  func animateAlwaysRunsTheChange(reduceMotion: Bool) {
    var ran = false
    Motion.animate(reduceMotion: reduceMotion) { ran = true }
    #expect(ran)
  }

  @Test func pingHaloFollowsTheTailwindKeyframes() {
    let start = PingDot.halo(at: 0)
    #expect(abs(start.scale - 1) < 1e-6)
    #expect(abs(start.opacity - 1) < 1e-6)
    // `75%, 100% { transform: scale(2); opacity: 0 }`: the halo holds at the end.
    for time in [0.75, 0.9] {
      let end = PingDot.halo(at: time)
      #expect(abs(end.scale - 2) < 1e-6)
      #expect(abs(end.opacity) < 1e-6)
    }
    let middle = PingDot.halo(at: 0.3)
    #expect(middle.scale > 1 && middle.scale < 2)
    // The cycle restarts every second.
    #expect(abs(PingDot.halo(at: 12.3).scale - middle.scale) < 1e-6)
  }
}

@Suite struct SingleLineNormalization {
  @Test func lineBreaksBecomeOneSpaceEach() {
    #expect(TextNormalization.singleLine("a\r\nb") == "a b")
    #expect(TextNormalization.singleLine("a\rb\nc") == "a b c")
    #expect(TextNormalization.singleLine("a\n\nb") == "a  b")
    #expect(TextNormalization.singleLine("fim\n") == "fim ")
  }

  @Test func textWithoutBreaksIsUntouched() {
    #expect(TextNormalization.singleLine("") == "")
    #expect(TextNormalization.singleLine("uma linha só\t com tab") == "uma linha só\t com tab")
  }
}

@Suite struct PanelMaterialResolution {
  private let light = Theme.resolve(scheme: .light, backdrop: .mesh, density: .comfortable)
  private let dark = Theme.resolve(scheme: .dark, backdrop: .mesh, density: .comfortable)

  @Test func liquidGlassIsTheDefault() {
    #expect(EnvironmentValues().panelMaterial == .liquidGlass)
  }

  @Test func panelFollowsTheMaterial() {
    let panel = GlassRole.panel
    #expect(
      panel.fill(in: light, material: .liquidGlass, reduceTransparency: false, scheme: .light)
        == .glass(panel.glass(in: light)))
    #expect(
      panel.fill(in: light, material: .clearGlass, reduceTransparency: false, scheme: .light)
        == .dimmedGlass(Glass.clear))
    #expect(
      panel.fill(in: dark, material: .clearGlass, reduceTransparency: false, scheme: .dark)
        == .glass(Glass.clear))
    #expect(
      panel.fill(in: dark, material: .standard, reduceTransparency: false, scheme: .dark)
        == .material(tint: dark.surface2.opacity(panel.tintOpacity)))
  }

  @Test(arguments: PanelMaterial.allCases)
  func reduceTransparencyMakesThePanelOpaque(material: PanelMaterial) {
    #expect(
      GlassRole.panel.fill(in: dark, material: material, reduceTransparency: true, scheme: .dark)
        == .opaque(dark.surface2))
  }

  @Test(arguments: [GlassRole.bar, .popover, .pill], PanelMaterial.allCases)
  func controlsKeepRegularLiquidGlass(role: GlassRole, material: PanelMaterial) {
    for reduceTransparency in [false, true] {
      #expect(
        role.fill(in: light, material: material, reduceTransparency: reduceTransparency, scheme: .light)
          == .glass(role.glass(in: light)))
    }
  }
}
