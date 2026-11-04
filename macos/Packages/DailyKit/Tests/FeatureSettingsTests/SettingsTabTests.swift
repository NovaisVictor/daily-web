import DailyCore
import Testing

@testable import FeatureSettings

@Suite struct SettingsTabTests {
  @Test func mirrorsEveryCoreDestination() {
    for destination in SettingsDestination.allCases {
      #expect(SettingsTab(destination).rawValue == destination.rawValue)
    }
    #expect(SettingsTab.allCases.count == SettingsDestination.allCases.count)
  }
}
