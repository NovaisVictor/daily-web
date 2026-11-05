import DailyCore
import DailyModels
import SwiftUI
import Testing

@testable import FeatureShell

/// A registry deliberately out of order, so the tests prove the shell sorts it.
private let registry = ModuleRegistry(
  entries: [
    entry(.configuracao, nil),
    entry(.access, nil),
    entry(.module(.slack), .slack),
    entry(.module(ModuleID(rawValue: "future")), ModuleID(rawValue: "future")),
    entry(.ferramentas, nil),
    entry(.module(.email), .email),
    entry(.agents, nil),
    entry(.module(.agenda), .agenda),
    entry(.perfil, nil),
    entry(.module(.tasks), .tasks),
    entry(.kanban, nil),
    entry(.today, nil),
    entry(.module(.notes), .notes),
    entry(.module(.pulls), .pulls),
    entry(.module(.jira), .jira),
  ]
)

private func entry(_ route: AppRoute, _ module: ModuleID?) -> ModuleEntry {
  ModuleEntry(route: route, title: "\(route)", systemImage: "circle", requiresModule: module) { AnyView(EmptyView()) }
}

@Suite struct SidebarModelTests {
  @Test func allModulesOnFollowTheWebOrder() {
    let model = SidebarModel(registry: registry, enabled: ModuleID.known + [ModuleID(rawValue: "future")])
    #expect(model.sections.map(\.id) == ["pages", "modules", "settings"])
    #expect(model.sections.map(\.title) == [nil, "Módulos", "Ajustes"])
    #expect(model.sections[0].entries.map(\.route) == [.today, .kanban, .ferramentas])
    #expect(
      model.sections[1].entries.map(\.route) == [
        .module(.email), .module(.tasks), .module(.notes), .module(.agenda), .module(.jira),
        .module(.pulls), .module(.slack), .module(ModuleID(rawValue: "future")),
      ]
    )
    #expect(model.sections[2].entries.map(\.route) == [.access, .configuracao])
  }

  @Test func perfilAndTheAgentsWorkspaceHaveNoRowButStayReachable() {
    let model = SidebarModel(registry: registry, enabled: [])
    #expect(!model.orderedEntries.contains { $0.route == .perfil || $0.route == .agents })
    #expect(model.entry(for: .perfil) != nil)
    #expect(model.entry(for: .agents) != nil)
    #expect(model.resolvedSelection(.agents) == .agents)
    #expect(model.resolvedSelection(.perfil) == .perfil)
  }

  @Test func onlyEnabledModulesShow() {
    let model = SidebarModel(registry: registry, enabled: [.slack, .tasks])
    #expect(
      model.orderedEntries.map(\.route) == [
        .today, .kanban, .ferramentas, .module(.tasks), .module(.slack), .access, .configuracao,
      ]
    )
  }

  @Test func noModulesDropsTheEmptySection() {
    let model = SidebarModel(registry: registry, enabled: [])
    #expect(model.sections.map(\.id) == ["pages", "settings"])
    #expect(model.orderedEntries.map(\.route) == [.today, .kanban, .ferramentas, .access, .configuracao])
  }

  @Test func selectionOfASwitchedOffModuleFallsBackToInicio() {
    let model = SidebarModel(registry: registry, enabled: [.tasks])
    #expect(model.resolvedSelection(.module(.email)) == .today)
    #expect(model.resolvedSelection(.module(.tasks)) == .module(.tasks))
    #expect(model.resolvedSelection(.kanban) == .kanban)
    #expect(model.resolvedSelection(nil) == nil)
  }

  @Test func fallbackWithoutInicioPicksTheFirstRow() {
    let noToday = ModuleRegistry(entries: [entry(.module(.notes), .notes), entry(.access, nil)])
    let model = SidebarModel(registry: noToday, enabled: [])
    #expect(model.resolvedSelection(.module(.notes)) == .access)
    #expect(SidebarModel(registry: ModuleRegistry(entries: []), enabled: []).resolvedSelection(.today) == nil)
  }

  @Test func paletteListsTheRowsThenPerfilAndTheWorkspace() {
    let model = SidebarModel(registry: registry, enabled: [.email])
    #expect(
      model.paletteEntries.map(\.route) == [
        .today, .kanban, .ferramentas, .module(.email), .access, .configuracao, .perfil, .agents,
      ]
    )
  }
}
