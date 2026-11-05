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
      AppCommands(environment: delegate.environment, opener: delegate.opener)
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

    // Configuração is a page of the main window (spec 012 FR-012-05). The scene stays
    // only so `openSettings()` from a screen still lands there; ⌘, is `AppCommands`.
    Settings {
      SettingsRedirect(environment: delegate.environment, opener: delegate.opener)
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
/// would pick a scene on its own. ⌘, opens Configuração in the main window instead of
/// a Settings window.
struct AppCommands: Commands {
  let environment: AppEnvironment
  let opener: WindowOpener
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    CommandGroup(replacing: .newItem) {
      Button("Nova janela") { openWindow(id: SceneID.extraMain) }
        .keyboardShortcut("n", modifiers: .command)
    }
    CommandGroup(replacing: .appSettings) {
      Button("Ajustes…") {
        environment.navigator.open(.configuracao)
        opener.showMain(.settings)
      }
      .keyboardShortcut(",", modifiers: .command)
    }
  }
}

/// What the Settings scene shows when a screen still calls `openSettings()`: it sends
/// the request to the matching page of the main window and closes itself.
// TODO: remove with the Settings scene once Home and Access open `.ferramentas`
// through the navigator instead of `openSettings()`.
struct SettingsRedirect: View {
  let environment: AppEnvironment
  let opener: WindowOpener
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    Color.clear
      .frame(width: 1, height: 1)
      .onAppear(perform: redirect)
      .onChange(of: environment.navigator.requestedSettingsTab) { redirect() }
  }

  private func redirect() {
    let page = environment.navigator.takeRequestedSettingsTab().map(SettingsPage.init) ?? .configuracao
    environment.navigator.open(page.route)
    dismiss()
    opener.showMain(.settings)
  }
}

extension SettingsPage {
  var route: AppRoute {
    switch self {
    case .ferramentas: .ferramentas
    case .configuracao: .configuracao
    case .perfil: .perfil
    }
  }
}

extension View {
  /// The Mac section of Configuração needs the app's own controls.
  func generalSettingsControls() -> some View {
    environment(
      \.generalSettingsControls,
      GeneralSettingsControls(shortcutRecorder: GlobalShortcutRecorder(), launchAtLogin: LaunchAtLoginToggle())
    )
  }
}
