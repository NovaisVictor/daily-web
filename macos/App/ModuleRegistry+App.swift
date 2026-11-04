import DailyCore
import DailyModels
import FeatureAccess
import FeatureAgenda
import FeatureAgents
import FeatureEmail
import FeatureHome
import FeatureJira
import FeatureNotes
import FeaturePulls
import FeatureSlack
import FeatureTasks
import SwiftUI

extension ModuleRegistry {
  /// Every sidebar entry; titles come from `lib/modules.ts` and `nav-items.ts`.
  static func app(environment: AppEnvironment) -> ModuleRegistry {
    ModuleRegistry(entries: [
      entry(.today, "Hoje", "sun.max", nil) { HomeScreen(environment: environment) },
      entry(.module(.email), "E-mail", "envelope", .email) { EmailScreen(environment: environment) },
      entry(.module(.tasks), "Tarefas", "checklist", .tasks) { TasksScreen(environment: environment) },
      entry(.module(.notes), "Notas rápidas", "note.text", .notes) { NotesScreen(environment: environment) },
      entry(.module(.agenda), "Agenda", "calendar", .agenda) { AgendaScreen(environment: environment) },
      entry(.module(.jira), "Jira", "list.bullet.rectangle", .jira) { JiraScreen(environment: environment) },
      entry(.module(.pulls), "Pull requests", "arrow.triangle.pull", .pulls) { PullsScreen(environment: environment) },
      entry(.module(.slack), "Slack", "bubble.left.and.bubble.right", .slack) { SlackScreen(environment: environment) },
      entry(.agents, "Agentes", "cpu", nil) { AgentsScreen(environment: environment) },
      entry(.access, "Acesso dos agentes", "key", nil) { AccessScreen(environment: environment) },
    ])
  }

  private static func entry(
    _ route: AppRoute,
    _ title: String,
    _ symbol: String,
    _ module: ModuleID?,
    @ViewBuilder view: @escaping () -> some View
  ) -> ModuleEntry {
    ModuleEntry(route: route, title: title, systemImage: symbol, requiresModule: module) { AnyView(view()) }
  }

  private static func entry(_ route: AppRoute, _ title: String, _ symbol: String, _ module: ModuleID?) -> ModuleEntry {
    entry(route, title, symbol, module) { ComingSoonView(title: title) }
  }
}

/// Placeholder for a screen whose feature has not landed yet.
struct ComingSoonView: View {
  let title: String

  var body: some View {
    ContentUnavailableView(title, systemImage: "hammer", description: Text("Em construção."))
  }
}
