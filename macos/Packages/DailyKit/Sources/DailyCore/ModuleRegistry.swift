import DailyModels
import SwiftUI

// FROZEN INTERFACE (T006). The shell builds navigation from this registry, and
// the app target fills it with each feature's root view, so the shell never
// imports a feature.

/// A place in the main window's sidebar.
public enum AppRoute: Hashable, Sendable {
  case today
  case module(ModuleID)
  case agents
  case access
}

/// One sidebar entry and the view it shows.
public struct ModuleEntry: Identifiable {
  public let route: AppRoute
  public let title: String
  /// SF Symbol name.
  public let systemImage: String
  /// Module that must be on in `DashboardState.modules` for the entry to show;
  /// nil for entries that are always there (Hoje, Agentes, Acesso).
  public let requiresModule: ModuleID?
  public let makeView: () -> AnyView

  public var id: AppRoute { route }

  public init(
    route: AppRoute,
    title: String,
    systemImage: String,
    requiresModule: ModuleID?,
    makeView: @escaping () -> AnyView
  ) {
    self.route = route
    self.title = title
    self.systemImage = systemImage
    self.requiresModule = requiresModule
    self.makeView = makeView
  }
}

/// The ordered set of entries the app offers.
public struct ModuleRegistry {
  public let entries: [ModuleEntry]

  public init(entries: [ModuleEntry]) {
    self.entries = entries
  }

  /// Entries to show given the modules the server reports as on.
  public func visibleEntries(enabled: [ModuleID]) -> [ModuleEntry] {
    entries.filter { entry in
      guard let module = entry.requiresModule else { return true }
      return enabled.contains(module)
    }
  }

  public func entry(for route: AppRoute) -> ModuleEntry? {
    entries.first { $0.route == route }
  }
}
