import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// The tabs of the Settings scene (⌘,).
public enum SettingsTab: String, CaseIterable, Hashable, Sendable {
  case appearance, integrations, profile, users, general
}

/// The app's settings: the web's `/config`, `/tools` and `/perfil` pages in one
/// Settings window. The panel layout tab of the web does not apply: the app
/// has no draggable grid (`docs/spec.md`, "Fora de escopo").
public struct SettingsScreen: View {
  private let environment: AppEnvironment
  @State private var selection: SettingsTab

  public init(environment: AppEnvironment) {
    self.init(environment: environment, initialTab: .appearance)
  }

  public init(environment: AppEnvironment, initialTab: SettingsTab) {
    self.environment = environment
    _selection = State(initialValue: initialTab)
  }

  public var body: some View {
    TabView(selection: $selection) {
      Tab("Aparência", systemImage: "paintbrush", value: SettingsTab.appearance) {
        AppearanceSettingsView(preferences: environment.preferences)
      }
      Tab("Integrações", systemImage: "puzzlepiece.extension", value: SettingsTab.integrations) {
        IntegrationsSettingsView(environment: environment)
      }
      Tab("Perfil", systemImage: "person.crop.circle", value: SettingsTab.profile) {
        ProfileSettingsView(environment: environment)
      }
      Tab("Usuários", systemImage: "person.2", value: SettingsTab.users) {
        UsersSettingsView(environment: environment)
      }
      Tab("Geral", systemImage: "gearshape", value: SettingsTab.general) {
        GeneralSettingsView()
      }
    }
    .frame(minWidth: 620, idealWidth: 680, minHeight: 460, idealHeight: 560)
  }
}

/// Global shortcut and launch at login; T501 fills these in.
struct GeneralSettingsView: View {
  var body: some View {
    Form {
      Section("Atalho global") {
        EmptyView()
      }
      Section("Abrir ao iniciar") {
        EmptyView()
      }
    }
    .formStyle(.grouped)
  }
}

#Preview {
  SettingsScreen(environment: .preview())
}
