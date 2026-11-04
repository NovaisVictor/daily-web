import DailyCore
import DailyModels
import SwiftUI
import Testing

@testable import FeatureShell

private func entry(_ route: AppRoute, _ title: String, _ module: ModuleID?) -> ModuleEntry {
  ModuleEntry(route: route, title: title, systemImage: "circle", requiresModule: module) { AnyView(EmptyView()) }
}

@Suite struct ShellMenuTests {
  private let registry = ModuleRegistry(entries: [
    entry(.today, "Hoje", nil),
    entry(.module(.email), "E-mail", .email),
    entry(.module(.tasks), "Tarefas", .tasks),
    entry(.module(.notes), "Notas rápidas", .notes),
    entry(.module(.agenda), "Agenda", .agenda),
    entry(.module(.jira), "Jira", .jira),
    entry(.module(.pulls), "Pull requests", .pulls),
    entry(.module(.slack), "Slack", .slack),
    entry(.agents, "Agentes", nil),
    entry(.access, "Acesso dos agentes", nil),
  ])

  @Test func digitsFollowTheSidebarAndStopAtNine() {
    let sidebar = SidebarModel(registry: registry, enabled: ModuleID.known)
    let items = ShellShortcuts.goMenuItems(sidebar.orderedEntries)
    #expect(items.map(\.title) == sidebar.orderedEntries.map(\.title))
    #expect(items.map(\.key) == ["1", "2", "3", "4", "5", "6", "7", "8", "9", nil])
    #expect(items[2].route == .module(.tasks))
    #expect(items[8].route == .agents)
    #expect(items[9].route == .access)
  }

  @Test func switchedOffModulesMoveTheDigits() {
    let sidebar = SidebarModel(registry: registry, enabled: [.tasks])
    let items = ShellShortcuts.goMenuItems(sidebar.orderedEntries)
    #expect(items.map(\.route) == [.today, .module(.tasks), .agents, .access])
    #expect(items.map(\.key) == ["1", "2", "3", "4"])
  }

  @Test func noEntriesNoItems() {
    #expect(ShellShortcuts.goMenuItems([]).isEmpty)
  }
}
