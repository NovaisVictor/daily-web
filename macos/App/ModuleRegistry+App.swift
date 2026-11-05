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
import FeatureSettings
import FeatureSlack
import FeatureTasks
import SwiftUI

extension ModuleRegistry {
  /// Every page of the main window. Titles come from `components/shell/nav-items.ts`
  /// and `lib/modules.ts`; the shell sorts them into the sidebar's sections.
  static func app(environment: AppEnvironment) -> ModuleRegistry {
    ModuleRegistry(entries: [
      entry(.today, "Início", "house", nil) { HomeScreen(environment: environment) },
      entry(.kanban, "Kanban", "rectangle.split.3x1", nil) { AgentsScreen(environment: environment, mode: .kanban) },
      entry(.ferramentas, "Ferramentas", "powerplug", nil) { FerramentasScreen(environment: environment) },
      entry(.module(.email), "E-mail", "envelope", .email) { EmailScreen(environment: environment) },
      entry(.module(.tasks), "Tarefas", "checklist", .tasks) { TasksScreen(environment: environment) },
      entry(.module(.notes), "Notas rápidas", "note.text", .notes) { NotesScreen(environment: environment) },
      entry(.module(.agenda), "Agenda", "calendar", .agenda) { AgendaScreen(environment: environment) },
      entry(.module(.jira), "Jira", "list.bullet.rectangle", .jira) { JiraScreen(environment: environment) },
      entry(.module(.pulls), "GitHub", "arrow.triangle.pull", .pulls) { PullsScreen(environment: environment) },
      entry(.module(.slack), "Slack", "bubble.left.and.bubble.right", .slack) { SlackScreen(environment: environment) },
      entry(.access, "Acesso dos agentes", "key", nil) { AccessScreen(environment: environment) },
      entry(.configuracao, "Configuração", "slider.horizontal.3", nil) { ConfiguracaoScreen(environment: environment) },
      entry(.perfil, "Perfil", "person.crop.circle", nil) { PerfilScreen(environment: environment) },
      entry(.agents, "Agentes e atividades", "rectangle.3.group", nil) {
        AgentsScreen(environment: environment, mode: .workspace)
      },
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
