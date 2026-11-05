import SwiftUI
import Testing

@testable import DailyDesign

private let light = Theme.resolve(scheme: .light, backdrop: .mesh, density: .comfortable)
private let dark = Theme.resolve(scheme: .dark, backdrop: .mesh, density: .comfortable)

@Suite struct PillButtonMapping {
  @Test func primaryUsesTheBrandFaceAndButtonShadow() {
    let palette = PillButtonStyle.palette(.primary, hovering: false, theme: light, scheme: .light)
    #expect(palette == PillPalette(fill: light.brand, foreground: light.brandInk, shadow: .button))
    // Hover brightens the face; it never swaps the fill.
    #expect(PillButtonStyle.palette(.primary, hovering: true, theme: light, scheme: .light) == palette)
  }

  @Test func outlineIsRimmedAndLiftsOnHover() {
    let rest = PillButtonStyle.palette(.outline, hovering: false, theme: light, scheme: .light)
    #expect(rest == PillPalette(fill: light.surface2, foreground: light.ink, border: light.lineStrong, shadow: .e1))
    let hover = PillButtonStyle.palette(.outline, hovering: true, theme: light, scheme: .light)
    #expect(hover.fill == light.lineSoft)
    #expect(hover.shadow == .e2)
  }

  @Test func ghostHasNothingAtRest() {
    let rest = PillButtonStyle.palette(.ghost, hovering: false, theme: dark, scheme: .dark)
    #expect(rest == PillPalette(fill: .clear, foreground: dark.ink))
    #expect(
      PillButtonStyle.palette(.ghost, hovering: true, theme: dark, scheme: .dark).fill == dark.lineSoft.opacity(0.5))
    #expect(PillButtonStyle.palette(.ghost, hovering: true, theme: light, scheme: .light).fill == light.lineSoft)
  }

  @Test func destructiveIsDangerWithWhiteText() {
    let lightRest = PillButtonStyle.palette(.destructive, hovering: false, theme: light, scheme: .light)
    #expect(lightRest.fill == light.danger.opacity(1))
    #expect(lightRest.foreground == .white)
    #expect(
      PillButtonStyle.palette(.destructive, hovering: true, theme: light, scheme: .light).fill
        == light.danger.opacity(0.9))
    #expect(
      PillButtonStyle.palette(.destructive, hovering: false, theme: dark, scheme: .dark).fill
        == dark.danger.opacity(0.6))
  }

  @Test func pressingDropsTheShadow() {
    #expect(PillButtonStyle.pressedShadow(.primary) == .e1)
    for variant in [PillButtonVariant.outline, .ghost, .destructive] {
      #expect(PillButtonStyle.pressedShadow(variant) == ControlShadow.none)
    }
  }

  /// button.tsx: `sm` is h-8 px-3.5 gap-1.5, `default` is h-9 px-5 gap-2.
  @Test func sizesMatchTheWeb() {
    #expect(PillButtonSize.small.height == 32)
    #expect(PillButtonSize.small.horizontalPadding == 14)
    #expect(PillButtonSize.small.spacing == 6)
    #expect(PillButtonSize.medium.height == 36)
    #expect(PillButtonSize.medium.horizontalPadding == 20)
    #expect(PillButtonSize.medium.spacing == 8)
  }
}

@Suite struct IconButtonMapping {
  @Test func sizes() {
    #expect(IconButtonSize.allCases.map(\.side) == [24, 28, 32])
  }

  @Test func ghostGainsItsRimOnlyWhenHighlighted() {
    let rest = IconButtonStyle.palette(.ghost, highlighted: false, theme: light)
    #expect(rest.fill == .clear)
    #expect(rest.border == .clear)
    #expect(rest.foreground == light.inkDim)
    let hover = IconButtonStyle.palette(.ghost, highlighted: true, theme: light)
    #expect(hover == PillPalette(fill: light.surface3, foreground: light.ink, border: light.line))
  }

  @Test func outlineIsTheJiraSortCircle() {
    let rest = IconButtonStyle.palette(.outline, highlighted: false, theme: dark)
    #expect(rest == PillPalette(fill: dark.surface2, foreground: dark.inkMid, border: dark.lineStrong, shadow: .e1))
    #expect(IconButtonStyle.palette(.outline, highlighted: true, theme: dark).foreground == dark.ink)
  }
}

@Suite struct ChipMapping {
  @Test func litChipUsesTheNeutralControlRim() {
    #expect(
      Chip.palette(isOn: true, hovering: false, theme: light)
        == PillPalette(fill: light.brandTint, foreground: light.ink, border: light.brandEdge, shadow: .control)
    )
  }

  @Test func offChipHovers() {
    #expect(Chip.palette(isOn: false, hovering: false, theme: light).foreground == light.inkMid)
    let hover = Chip.palette(isOn: false, hovering: true, theme: light)
    #expect(hover.fill == light.lineSoft)
    #expect(hover.foreground == light.ink)
  }
}

@Suite struct ControlShadows {
  /// globals.css:50-51 (light) and :310-311 (dark).
  @Test func dropsFollowTheScheme() {
    #expect(ControlShadow.none.layers(scheme: .light).isEmpty)
    #expect(ControlShadow.e1.layers(scheme: .light) == [.init(opacity: 0.05, radius: 0, y: 1)])
    #expect(
      ControlShadow.e2.layers(scheme: .dark)
        == [.init(opacity: 0.35, radius: 0, y: 1), .init(opacity: 0.30, radius: 1, y: 4)]
    )
    #expect(ControlShadow.control.layers(scheme: .light) == ControlShadow.e2.layers(scheme: .light))
  }

  /// `--control-rim`: white 85% in light (:144), 16% in dark (:304).
  @Test func controlRim() {
    #expect(ControlShadow.control.rimOpacity(scheme: .light) == 0.85)
    #expect(ControlShadow.control.rimOpacity(scheme: .dark) == 0.16)
    #expect(ControlShadow.e1.rimOpacity(scheme: .light) == 0)
  }
}

@Suite struct SegmentedPillsLogic {
  @Test(arguments: [(0, 1, 3, 1), (2, 1, 3, 0), (0, -1, 3, 2), (1, -1, 2, 0)])
  func arrowsWrap(from: Int, step: Int, count: Int, expected: Int) {
    #expect(SegmentedPillsStyle.index(from: from, step: step, count: count) == expected)
  }

  @Test func accessibleNameJoinsTheCount() {
    #expect(SegmentedPillsStyle.accessibilityLabel("Entregues", count: 2) == "Entregues, 2")
    #expect(SegmentedPillsStyle.accessibilityLabel("Entregues", count: 0) == "Entregues")
    #expect(SegmentedPillsStyle.accessibilityLabel("Lista", count: nil) == "Lista")
  }

  @Test func activePillFill() {
    #expect(
      SegmentedPillsStyle.tabs.pillPalette(isSelected: true, hovering: false, theme: light).fill == light.surface3)
    #expect(
      SegmentedPillsStyle.toggle.pillPalette(isSelected: true, hovering: false, theme: light).fill == light.brandTint)
    for style in SegmentedPillsStyle.allCases {
      #expect(style.pillPalette(isSelected: true, hovering: false, theme: light).shadow == .control)
      #expect(style.pillPalette(isSelected: false, hovering: true, theme: light).foreground == light.ink)
    }
  }

  /// legacy-tabs.tsx h-8 p-[3px]; segmented.ts h-7 p-0.5.
  @Test func geometry() {
    #expect(SegmentedPillsStyle.tabs.pillHeight == 32)
    #expect(SegmentedPillsStyle.tabs.groupInset == 3)
    #expect(SegmentedPillsStyle.toggle.pillHeight == 28)
    #expect(SegmentedPillsStyle.toggle.groupInset == 2)
  }
}

@Suite struct ListRowLogic {
  /// `even:` is 1-based in CSS: the second row (index 1) is the first striped one.
  @Test func zebraParity() {
    #expect((0..<6).map(ListRowStyle.isStriped(index:)) == [false, true, false, true, false, true])
  }

  @Test func backgrounds() {
    #expect(ListRowStyle.background(index: 0, hovering: false, isActive: false, theme: light) == .clear)
    #expect(
      ListRowStyle.background(index: 1, hovering: false, isActive: false, theme: light) == light.lineSoft.opacity(0.25))
    #expect(ListRowStyle.background(index: 1, hovering: true, isActive: false, theme: light) == light.brandTint)
    #expect(ListRowStyle.background(index: 0, hovering: false, isActive: true, theme: light) == light.brandTint)
  }

  @Test func paddingFollowsDensity() {
    #expect(ListRowStyle.horizontalPadding == 8)
    #expect(Theme.resolve(scheme: .light, backdrop: .mesh, density: .comfortable).metrics.rowVerticalPadding == 12)
    #expect(Theme.resolve(scheme: .light, backdrop: .mesh, density: .compact).metrics.rowVerticalPadding == 8)
  }

  @Test func activeRow() {
    #expect(ActiveRowStyle.barWidth == 3)
    #expect(ActiveRowStyle.foreground(isActive: true, hovering: false, theme: light) == light.ink)
    #expect(ActiveRowStyle.foreground(isActive: false, hovering: false, theme: light) == light.inkMid)
    #expect(ActiveRowStyle.barGlowRadius(scheme: .dark) == 4)
    #expect(ActiveRowStyle.barGlowRadius(scheme: .light) == 0)
  }
}

@Suite struct RepoPillAndCountSlot {
  @Test func repoPill() {
    #expect(RepoPill.removeLabel(for: "acme/api") == "remover acme/api")
    #expect(RepoPill.palette(theme: light).shadow == .e1)
    #expect(RepoPill.palette(theme: light).border == light.lineStrong)
  }

  @Test func countSlotAlwaysHasText() {
    #expect(CountSlot.text(for: 0) == "0")
    #expect(!CountSlot.isLit(0))
    #expect(CountSlot.text(for: 12) == "12")
    #expect(CountSlot.isLit(12))
  }
}
