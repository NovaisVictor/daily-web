import DailyCore
import DailyModels

/// `AppRoute` as a window's value: `WindowGroup(for:)` needs `Codable` to restore
/// the window, and the frozen `AppRoute` is not.
struct WindowRoute: Codable, Hashable {
  private enum Kind: String, Codable {
    case today, module, agents, access, kanban, ferramentas, configuracao, perfil
  }

  private let kind: Kind
  /// The module's raw value, only for `.module`.
  private let module: String?

  init(_ route: AppRoute) {
    switch route {
    case .today: (kind, module) = (.today, nil)
    case .agents: (kind, module) = (.agents, nil)
    case .access: (kind, module) = (.access, nil)
    case .kanban: (kind, module) = (.kanban, nil)
    case .ferramentas: (kind, module) = (.ferramentas, nil)
    case .configuracao: (kind, module) = (.configuracao, nil)
    case .perfil: (kind, module) = (.perfil, nil)
    case .module(let id): (kind, module) = (.module, id.rawValue)
    }
  }

  /// Nil for a module window whose stored value lost its module id.
  var route: AppRoute? {
    switch kind {
    case .today: .today
    case .agents: .agents
    case .access: .access
    case .kanban: .kanban
    case .ferramentas: .ferramentas
    case .configuracao: .configuracao
    case .perfil: .perfil
    case .module: module.map { .module(ModuleID(rawValue: $0)) }
    }
  }
}

/// The scenes' ids, shared by the scenes and whoever opens them.
enum SceneID {
  /// The one main window, reopened by the menu bar, the Dock and the global shortcut.
  static let main = "main"
  /// More main windows (⌘N), each with its own sidebar selection.
  static let extraMain = "extra-main"
  /// One module's screen alone.
  static let module = "module"
}
