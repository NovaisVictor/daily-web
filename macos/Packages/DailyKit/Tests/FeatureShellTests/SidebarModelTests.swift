import DailyCore
import DailyModels
import SwiftUI
import Testing

@testable import FeatureShell

/// A registry deliberately out of order, so the tests prove the shell sorts it.
private let registry = ModuleRegistry(
  entries: [
    entry(.access, nil),
    entry(.module(.slack), .slack),
    entry(.module(ModuleID(rawValue: "future")), ModuleID(rawValue: "future")),
    entry(.module(.email), .email),
    entry(.agents, nil),
    entry(.module(.agenda), .agenda),
    entry(.module(.tasks), .tasks),
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
    #expect(model.sections.map(\.id) == ["today", "modules", "settings"])
    #expect(model.sections.map(\.title) == [nil, nil, "Ajustes"])
    #expect(
      model.orderedEntries.map(\.route) == [
        .today,
        .module(.email), .module(.tasks), .module(.notes), .module(.agenda), .module(.jira),
        .module(.pulls), .module(.slack), .module(ModuleID(rawValue: "future")),
        .agents, .access,
      ]
    )
  }

  @Test func onlyEnabledModulesShow() {
    let model = SidebarModel(registry: registry, enabled: [.slack, .tasks])
    #expect(model.orderedEntries.map(\.route) == [.today, .module(.tasks), .module(.slack), .agents, .access])
  }

  @Test func noModulesDropsTheEmptySection() {
    let model = SidebarModel(registry: registry, enabled: [])
    #expect(model.sections.map(\.id) == ["today", "settings"])
    #expect(model.orderedEntries.map(\.route) == [.today, .agents, .access])
  }

  @Test func selectionOfASwitchedOffModuleFallsBackToToday() {
    let model = SidebarModel(registry: registry, enabled: [.tasks])
    #expect(model.resolvedSelection(.module(.email)) == .today)
    #expect(model.resolvedSelection(.module(.tasks)) == .module(.tasks))
    #expect(model.resolvedSelection(.agents) == .agents)
    #expect(model.resolvedSelection(nil) == nil)
  }

  @Test func fallbackWithoutTodayPicksTheFirstRow() {
    let noToday = ModuleRegistry(entries: [entry(.module(.notes), .notes), entry(.agents, nil)])
    let model = SidebarModel(registry: noToday, enabled: [])
    #expect(model.resolvedSelection(.module(.notes)) == .agents)
    #expect(SidebarModel(registry: ModuleRegistry(entries: []), enabled: []).resolvedSelection(.today) == nil)
  }

  @Test func shortcutsCoverTheFirstNineRows() {
    let model = SidebarModel(registry: registry, enabled: ModuleID.known + [ModuleID(rawValue: "future")])
    let shortcuts = ShellShortcuts.routeShortcuts(model.orderedEntries.map(\.route))
    #expect(shortcuts.count == 9)
    #expect(shortcuts.first?.key == "1")
    #expect(shortcuts.first?.route == .today)
    #expect(shortcuts.last?.key == "9")
    #expect(shortcuts.last?.route == .module(ModuleID(rawValue: "future")))
  }
}
