import DailyCore
import DailyModels
import SwiftUI

extension ModuleRegistry {
  /// Every sidebar entry. Feature waves (T3xx/T4xx) swap each placeholder for
  /// the feature's root view; titles come from `lib/modules.ts` and `nav-items.ts`.
  static func app(environment: AppEnvironment) -> ModuleRegistry {
    ModuleRegistry(entries: [
      entry(.today, "Hoje", "sun.max", nil),
      entry(.module(.email), "E-mail", "envelope", .email),
      entry(.module(.tasks), "Tarefas", "checklist", .tasks),
      entry(.module(.notes), "Notas rápidas", "note.text", .notes),
      entry(.module(.agenda), "Agenda", "calendar", .agenda),
      entry(.module(.jira), "Jira", "list.bullet.rectangle", .jira),
      entry(.module(.pulls), "Pull requests", "arrow.triangle.pull", .pulls),
      entry(.module(.slack), "Slack", "bubble.left.and.bubble.right", .slack),
      entry(.agents, "Agentes", "cpu", nil),
      entry(.access, "Acesso dos agentes", "key", nil),
    ])
  }

  private static func entry(_ route: AppRoute, _ title: String, _ symbol: String, _ module: ModuleID?) -> ModuleEntry {
    ModuleEntry(route: route, title: title, systemImage: symbol, requiresModule: module) {
      AnyView(ComingSoonView(title: title))
    }
  }
}

/// Placeholder for a screen whose feature has not landed yet.
struct ComingSoonView: View {
  let title: String

  var body: some View {
    ContentUnavailableView(title, systemImage: "hammer", description: Text("Em construção."))
  }
}
