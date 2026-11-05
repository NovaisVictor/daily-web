import DailyCore
import DailyModels
import SwiftUI

/// Fake data for previews; nothing here touches the network.
enum PreviewData {
  static let account = ShellAccount(displayName: "Ana Souza", username: "ana", avatar: nil)

  static let appearance = ShellAppearance(theme: .system, density: .comfortable, backdrop: .mesh)

  static let accountActions = ShellAccountActions(
    profile: {},
    connectAgent: {},
    agentsWorkspace: {},
    settings: {},
    setTheme: { _ in },
    setDensity: { _ in },
    setBackdrop: { _ in },
    signOut: {}
  )

  static let menuBarActions = MenuBarActions(
    openApp: {},
    openTasks: {},
    openTask: { _ in },
    openAgenda: {},
    openNotifications: {},
    togglePomodoro: {},
    resetPomodoro: {},
    quit: {}
  )

  static let registry = ModuleRegistry(
    entries: [
      placeholder(.today, "Início", "house", nil),
      placeholder(.kanban, "Kanban", "rectangle.split.3x1", nil),
      placeholder(.ferramentas, "Ferramentas", "powerplug", nil),
      placeholder(.module(.email), "E-mail", "envelope", .email),
      placeholder(.module(.tasks), "Tarefas", "checklist", .tasks),
      placeholder(.module(.notes), "Notas rápidas", "note.text", .notes),
      placeholder(.module(.agenda), "Agenda", "calendar", .agenda),
      placeholder(.module(.jira), "Jira", "list.bullet.rectangle", .jira),
      placeholder(.module(.pulls), "GitHub", "arrow.triangle.pull", .pulls),
      placeholder(.module(.slack), "Slack", "bubble.left.and.bubble.right", .slack),
      placeholder(.access, "Acesso dos agentes", "key", nil),
      placeholder(.configuracao, "Configuração", "slider.horizontal.3", nil),
      placeholder(.perfil, "Perfil", "person.crop.circle", nil),
      placeholder(.agents, "Agentes e atividades", "rectangle.3.group", nil),
    ]
  )

  static var paletteCommands: [PaletteCommand] {
    ShellCommands.standard(
      sidebar: SidebarModel(registry: registry, enabled: ModuleID.known),
      navigate: { _ in },
      setTheme: { _ in },
      setDensity: { _ in },
      setBackdrop: { _ in },
      profile: {},
      changePassword: {},
      changePhoto: {},
      appearance: {},
      signOut: {}
    )
  }

  private static func placeholder(
    _ route: AppRoute,
    _ title: String,
    _ systemImage: String,
    _ module: ModuleID?
  ) -> ModuleEntry {
    ModuleEntry(route: route, title: title, systemImage: systemImage, requiresModule: module) {
      AnyView(Text(title).typeRole(.title).frame(maxWidth: .infinity, maxHeight: .infinity))
    }
  }
}
