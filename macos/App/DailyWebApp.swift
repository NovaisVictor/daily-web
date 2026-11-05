import DailyCore
import FeatureSettings
import FeatureShell
import SwiftUI

@main
struct DailyWebApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

  var body: some Scene {
    // A single `Window` so the menu bar, the Dock and the global shortcut bring back
    // the same window instead of stacking new ones.
    Window("Daily Web", id: SceneID.main) {
      RootView(environment: delegate.environment, opener: delegate.opener, followsNavigator: true)
    }
    .defaultSize(width: 1180, height: 760)
    .commands {
      AppCommands()
      ShellMenuCommands()
    }

    WindowGroup("Daily Web", id: SceneID.extraMain) {
      RootView(environment: delegate.environment, opener: delegate.opener, followsNavigator: false)
    }
    .defaultSize(width: 1180, height: 760)

    WindowGroup("Daily Web", id: SceneID.module, for: WindowRoute.self) { $route in
      ModuleWindow(environment: delegate.environment, route: route?.route, opener: delegate.opener)
    }
    .defaultSize(width: 900, height: 640)

    Settings {
      ThemedRoot(preferences: delegate.environment.preferences) {
        SettingsScreen(environment: delegate.environment)
      }
      .environment(
        \.generalSettingsControls,
        GeneralSettingsControls(shortcutRecorder: GlobalShortcutRecorder(), launchAtLogin: LaunchAtLoginToggle())
      )
    }

    MenuBarExtra {
      // `MenuBarContent` applies the windows' palette and brand tint itself.
      MenuBarContent(environment: delegate.environment, opener: delegate.opener)
    } label: {
      MenuBarLabel(environment: delegate.environment, opener: delegate.opener)
    }
    .menuBarExtraStyle(.window)
  }
}

/// ⌘N opens another main window; it replaces the system's "Nova janela", which
/// would pick a scene on its own.
struct AppCommands: Commands {
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    CommandGroup(replacing: .newItem) {
      Button("Nova janela") { openWindow(id: SceneID.extraMain) }
        .keyboardShortcut("n", modifiers: .command)
    }
  }
}
