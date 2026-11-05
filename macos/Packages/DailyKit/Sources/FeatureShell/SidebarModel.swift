import DailyCore
import DailyModels

/// A titled group of sidebar rows.
public struct SidebarSection: Identifiable {
  public let id: String
  /// Nil when the group shows without a heading.
  public let title: String?
  public let entries: [ModuleEntry]
}

/// The sidebar's layout for one set of enabled modules (spec 012 FR-012-01): the web's
/// pages (Início, Kanban, Ferramentas), then "Módulos" in the web's panel order, then
/// "Ajustes" (`components/shell/nav-items.ts:17-33`). Perfil and "Agentes e atividades"
/// have no row, as on the web, but stay reachable from the avatar menu, the palette and
/// a clicked notification.
public struct SidebarModel {
  public static let pageRoutes: [AppRoute] = [.today, .kanban, .ferramentas]
  public static let settingsRoutes: [AppRoute] = [.access, .configuracao]
  /// Pages without a row, in the order the palette lists them after the rows.
  public static let unlistedRoutes: [AppRoute] = [.perfil, .agents]

  public let sections: [SidebarSection]
  /// Every visible entry, with a row or not; the detail shows any of them.
  public let reachableEntries: [ModuleEntry]

  public init(registry: ModuleRegistry, enabled: [ModuleID]) {
    let visible = registry.visibleEntries(enabled: enabled)
    reachableEntries = visible
    let modules = visible.filter { if case .module = $0.route { true } else { false } }
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
    let pick = { (routes: [AppRoute]) in
      routes.compactMap { route in visible.first { $0.route == route } }
    }

    sections = [
      SidebarSection(id: "pages", title: nil, entries: pick(Self.pageRoutes)),
      SidebarSection(id: "modules", title: "Módulos", entries: orderedModules),
      SidebarSection(id: "settings", title: "Ajustes", entries: pick(Self.settingsRoutes)),
    ]
    .filter { !$0.entries.isEmpty }
  }

  /// Every row, top to bottom.
  public var orderedEntries: [ModuleEntry] { sections.flatMap(\.entries) }

  /// The rows ⌘1…⌘9 reach: the pages, then the modules (FR-012-07). "Ajustes" has no digit.
  public var numberedEntries: [ModuleEntry] {
    sections.filter { $0.id != "settings" }.flatMap(\.entries)
  }

  /// The palette's "Ir para": the rows, then Perfil and "Agentes e atividades".
  public var paletteEntries: [ModuleEntry] {
    orderedEntries + Self.unlistedRoutes.compactMap { route in reachableEntries.first { $0.route == route } }
  }

  public func entry(for route: AppRoute) -> ModuleEntry? {
    reachableEntries.first { $0.route == route }
  }

  /// The selection to keep once the visible entries change. Nothing selected stays
  /// nothing; a route whose module was switched off falls back to Início, or to the
  /// first row when the registry has no Início.
  public func resolvedSelection(_ selection: AppRoute?) -> AppRoute? {
    guard let selection, entry(for: selection) == nil else { return selection }
    if entry(for: .today) != nil { return .today }
    return orderedEntries.first?.route
  }
}
