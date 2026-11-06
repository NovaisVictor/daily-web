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
/// would pick a scene on its own. ⌘, opens Configuração, a page of the main window
/// (spec 012 FR-012-05), since the app has no Settings scene.
struct AppCommands: Commands {
  let environment: AppEnvironment
  let opener: WindowOpener
  @Environment(\.openWindow) private var openWindow
  /// The key window's shell: a main window moves itself, a module window
  /// brings the main one forward.
  @FocusedValue(\.shellMenu) private var shell
  /// The key window's Início while it is on screen: whether it is arranging.
  @FocusedValue(\.homeArrangeMenu) private var arrangeMenu

  var body: some Commands {
    CommandGroup(replacing: .newItem) {
      Button("Nova janela") { openWindow(id: SceneID.extraMain) }
        .keyboardShortcut("n", modifiers: .command)
    }
    CommandGroup(after: .toolbar) {
      // Spec 010 FR-010-02: a keyboard path into arranging the Início grid,
      // and out of it again.
      Button(arrangeCommand.title, action: performArrangeCommand)
        .disabled(!canPerformArrangeCommand)
    }
    CommandGroup(replacing: .appSettings) {
      Button("Ajustes…") {
        environment.navigator.open(.configuracao)
        opener.showMain(.settings)
      }
      .keyboardShortcut(",", modifiers: .command)
    }
  }

  private var arrangeCommand: ArrangeMenuCommand { ArrangeMenuCommand(arrangeMenu) }

  private var canPerformArrangeCommand: Bool {
    switch arrangeCommand {
    case .organize: canOrganizePanels
    case .finish: arrangeMenu?.isSaving == false
    }
  }

  private func performArrangeCommand() {
    switch arrangeCommand {
    case .organize: organizePanels()
    case .finish: arrangeMenu?.finish()
    }
  }

  /// Read from the session and the dashboard, which live as long as the app:
  /// the Início store is replaced at sign-out, and its window may not be measured yet.
  private var canOrganizePanels: Bool {
    guard environment.session.user != nil else { return false }
    return !(environment.dashboard.state?.modules.isEmpty ?? true)
  }

  /// Takes the key window (else the main one) to Início, whose screen answers
  /// the request once it is key and measured.
  private func organizePanels() {
    if let shell {
      shell.select(.today)
    } else {
      environment.navigator.open(.today)
      opener.showMain(.menu)
    }
    environment.navigator.requestArrange()
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
