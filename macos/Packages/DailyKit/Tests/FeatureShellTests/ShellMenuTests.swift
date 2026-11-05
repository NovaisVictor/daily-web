import DailyCore
import DailyDesign
import DailyModels
import SwiftUI
import Testing

@testable import FeatureShell

private func entry(_ route: AppRoute, _ title: String, _ module: ModuleID?) -> ModuleEntry {
  ModuleEntry(route: route, title: title, systemImage: "circle", requiresModule: module) { AnyView(EmptyView()) }
}

@Suite struct ShellMenuTests {
  private let registry = ModuleRegistry(entries: [
    entry(.today, "Início", nil),
    entry(.kanban, "Kanban", nil),
    entry(.ferramentas, "Ferramentas", nil),
    entry(.module(.email), "E-mail", .email),
    entry(.module(.tasks), "Tarefas", .tasks),
    entry(.module(.notes), "Notas rápidas", .notes),
    entry(.module(.agenda), "Agenda", .agenda),
    entry(.module(.jira), "Jira", .jira),
    entry(.module(.pulls), "GitHub", .pulls),
    entry(.module(.slack), "Slack", .slack),
    entry(.access, "Acesso dos agentes", nil),
    entry(.configuracao, "Configuração", nil),
    entry(.perfil, "Perfil", nil),
    entry(.agents, "Agentes e atividades", nil),
  ])

  @Test func pagesTakeTheFirstDigitsThenTheModules() {
    let sidebar = SidebarModel(registry: registry, enabled: ModuleID.known)
    let items = ShellShortcuts.goMenuItems(sidebar)
    #expect(items.map(\.title) == sidebar.orderedEntries.map(\.title))
    #expect(items.prefix(3).map(\.route) == [.today, .kanban, .ferramentas])
    #expect(items.prefix(3).map(\.key) == ["1", "2", "3"])
    #expect(items[3].route == .module(.email))
    #expect(items.map(\.key) == ["1", "2", "3", "4", "5", "6", "7", "8", "9", nil, nil, nil])
    #expect(items[8].route == .module(.pulls))
    #expect(items[9].route == .module(.slack))
  }

  @Test func settingsRowsNeverTakeADigit() {
    let sidebar = SidebarModel(registry: registry, enabled: [.tasks])
    let items = ShellShortcuts.goMenuItems(sidebar)
    #expect(items.map(\.route) == [.today, .kanban, .ferramentas, .module(.tasks), .access, .configuracao])
    #expect(items.map(\.key) == ["1", "2", "3", "4", nil, nil])
  }

  @Test func unlistedPagesAreNotInTheGoMenu() {
    let items = ShellShortcuts.goMenuItems(SidebarModel(registry: registry, enabled: []))
    #expect(!items.contains { $0.route == .perfil || $0.route == .agents })
  }

  @Test func noEntriesNoItems() {
    #expect(ShellShortcuts.goMenuItems(SidebarModel(registry: ModuleRegistry(entries: []), enabled: [])).isEmpty)
  }

  @Test func paletteGoToFollowsTheWebPages() {
    let commands = ShellCommands.standard(
      sidebar: SidebarModel(registry: registry, enabled: [.email, .pulls]),
      navigate: { _ in }, setTheme: { _ in }, setDensity: { _ in }, setBackdrop: { _ in },
      profile: {}, changePassword: {}, changePhoto: {}, appearance: {}, signOut: {}
    )
    #expect(
      commands.filter { $0.group == "Ir para" }.map(\.title) == [
        "Início", "Kanban", "Ferramentas", "E-mail", "GitHub", "Acesso dos agentes", "Configuração", "Perfil",
        "Agentes e atividades",
      ]
    )
  }
}

@Suite struct AccountMenuLabelTests {
  @Test func labelsMatchTheWebMenu() {
    #expect(ThemePreference.allCases.map(AccountMenuLabels.theme) == ["Sistema", "Claro", "Escuro"])
    #expect(Density.allCases.map(AccountMenuLabels.density) == ["Confortável", "Compacto"])
    #expect(
      Backdrop.allCases.map(AccountMenuLabels.backdrop) == [
        "Gradiente", "Catppuccin", "Dracula (só no tema escuro)", "WezTerm (só no tema escuro)",
      ]
    )
  }
}
