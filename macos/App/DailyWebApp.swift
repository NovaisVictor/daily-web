import DailyCore
import SwiftUI

@main
struct DailyWebApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

  var body: some Scene {
    WindowGroup("Daily Web") {
      RootView(environment: delegate.environment, router: delegate.router)
    }
    .defaultSize(width: 1180, height: 760)

    Settings {
      // FeatureSettings (T305) replaces this placeholder.
      ThemedRoot(preferences: delegate.environment.preferences) {
        ComingSoonView(title: "Configurações")
          .frame(width: 520, height: 360)
      }
    }
  }
}
