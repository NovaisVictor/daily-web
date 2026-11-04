import DailyCore
import DailyModels
import SwiftUI

/// Fake data for previews; nothing here touches the network.
enum PreviewData {
  static let account = ShellAccount(displayName: "Ana Souza", username: "ana", avatar: nil)

  static let accountActions = ShellAccountActions(
    profile: {},
    connectAgent: {},
    settings: {},
    signOut: {}
  )

  static let menuBarActions = MenuBarActions(
    openApp: {},
    openTasks: {},
    openAgenda: {},
    openNotifications: {},
    togglePomodoro: {},
    resetPomodoro: {},
    quit: {}
  )

  static let registry = ModuleRegistry(
    entries: [
      placeholder(.today, "Hoje", "sun.max", nil),
      placeholder(.module(.email), "E-mail", "envelope", .email),
      placeholder(.module(.tasks), "Tarefas", "checklist", .tasks),
      placeholder(.module(.notes), "Notas", "note.text", .notes),
      placeholder(.module(.agenda), "Agenda", "calendar", .agenda),
      placeholder(.module(.jira), "Jira", "ticket", .jira),
      placeholder(.module(.pulls), "Pull requests", "arrow.triangle.pull", .pulls),
      placeholder(.module(.slack), "Slack", "bubble.left.and.bubble.right", .slack),
      placeholder(.agents, "Agentes", "cpu", nil),
      placeholder(.access, "Acesso dos agentes", "key", nil),
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
      AnyView(Text(title).font(.largeTitle).frame(maxWidth: .infinity, maxHeight: .infinity))
    }
  }
}
