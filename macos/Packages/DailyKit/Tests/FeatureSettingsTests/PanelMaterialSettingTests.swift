import DailyDesign
import Foundation
import Testing

@testable import FeatureSettings

@Suite struct PanelMaterialSettingTests {
  @Test func theDefaultIsTheRegularLiquidGlass() {
    #expect(PanelMaterial.defaultValue == .liquidGlass)
    #expect(PanelMaterial.storageKey == "io.github.novaisvictor.dailyweb.panelMaterial")
  }

  @Test(arguments: PanelMaterial.allCases)
  func theStoredRawValueRoundTrips(material: PanelMaterial) throws {
    let suite = "PanelMaterialSettingTests.\(material.rawValue)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(material.rawValue, forKey: PanelMaterial.storageKey)
    let stored = try #require(defaults.string(forKey: PanelMaterial.storageKey))
    #expect(PanelMaterial(rawValue: stored) == material)
  }

  @Test func anUnknownStoredValueIsNotAMaterial() {
    // `@AppStorage` then keeps `defaultValue`.
    #expect(PanelMaterial(rawValue: "frosted") == nil)
  }

  @Test func everyMaterialIsOfferedOnceWithADescription() {
    let offered = AppearanceSettingsView.materials.map(\.0)
    #expect(offered == PanelMaterial.allCases)
    #expect(AppearanceSettingsView.materials.allSatisfy { !$0.1.isEmpty && !$0.2.isEmpty })
  }
}
