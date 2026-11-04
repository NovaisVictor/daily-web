import DailyCore
import FeatureSettings
import SwiftUI

@main
struct DailyWebApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

  var body: some Scene {
    WindowGroup("Daily Web") {
      RootView(environment: delegate.environment)
    }
    .defaultSize(width: 1180, height: 760)

    Settings {
      ThemedRoot(preferences: delegate.environment.preferences) {
        SettingsScreen(environment: delegate.environment)
      }
    }
  }
}
