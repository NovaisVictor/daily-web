import DailyCore
import DailyDesign
import SwiftUI

// Composition root. T201 replaces the placeholder window with the shell, the
// stores and the module registry.
@main
struct DailyWebApp: App {
  var body: some Scene {
    WindowGroup("Daily Web") {
      Text("Daily Web")
        .frame(minWidth: 480, minHeight: 320)
    }
  }
}
