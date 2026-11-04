import DailyCore
import DailyModels

/// A titled group of sidebar rows.
public struct SidebarSection: Identifiable {
  public let id: String
  /// Nil when the group shows without a heading.
  public let title: String?
  public let entries: [ModuleEntry]
}

/// The sidebar's layout for one set of enabled modules: Hoje, then the modules in the
/// web's panel order, then the "Ajustes" group (`components/shell/nav-items.ts`).
public struct SidebarModel {
  public let sections: [SidebarSection]

  public init(registry: ModuleRegistry, enabled: [ModuleID]) {
    let visible = registry.visibleEntries(enabled: enabled)
    var today: [ModuleEntry] = []
    var modules: [ModuleEntry] = []
    var settings: [ModuleEntry] = []
    for entry in visible {
      switch entry.route {
      case .today: today.append(entry)
      case .module: modules.append(entry)
      case .agents, .access: settings.append(entry)
      }
    }
    // A module the server adds before this client knows it keeps the registry's order,
    // after the known ones, instead of disappearing.
    let rank = { (entry: ModuleEntry) -> Int in
      guard case .module(let id) = entry.route, let index = ModuleID.known.firstIndex(of: id) else {
        return ModuleID.known.count
      }
      return index
    }
    let orderedModules = modules.enumerated()
      .sorted { lhs, rhs in
        let (left, right) = (rank(lhs.element), rank(rhs.element))
        return left == right ? lhs.offset < rhs.offset : left < right
      }
      .map(\.element)
    let orderedSettings = [AppRoute.agents, .access].compactMap { route in
      settings.first { $0.route == route }
    }

    sections = [
      SidebarSection(id: "today", title: nil, entries: today),
      SidebarSection(id: "modules", title: nil, entries: orderedModules),
      SidebarSection(id: "settings", title: "Ajustes", entries: orderedSettings),
    ]
    .filter { !$0.entries.isEmpty }
  }

  /// Every row, top to bottom; ⌘1…⌘9 follow this order.
  public var orderedEntries: [ModuleEntry] { sections.flatMap(\.entries) }

  public func entry(for route: AppRoute) -> ModuleEntry? {
    orderedEntries.first { $0.route == route }
  }

  /// The selection to keep once the visible entries change. Nothing selected stays
  /// nothing; a route whose module was switched off falls back to Hoje, or to the first
  /// row when the registry has no Hoje.
  public func resolvedSelection(_ selection: AppRoute?) -> AppRoute? {
    guard let selection, entry(for: selection) == nil else { return selection }
    if entry(for: .today) != nil { return .today }
    return orderedEntries.first?.route
  }
}
