import DailyCore
import DailyModels
import FeatureAgenda
import FeatureEmail
import FeatureJira
import FeatureNotes
import FeaturePulls
import FeatureSlack
import FeatureTasks
import SwiftUI

extension ModulePanels {
  /// Each module's full panel for Início (spec 011), with "Abrir em nova
  /// janela" opening the module's own window.
  static func app(environment: AppEnvironment, opener: WindowOpener) -> ModulePanels {
    ModulePanels { module in
      let openWindow = { opener.open(.module(module)) }
      switch module {
      case .email: return AnyView(EmailPanel(environment: environment, onOpenWindow: openWindow))
      case .tasks: return AnyView(TasksPanel(environment: environment, onOpenWindow: openWindow))
      case .notes: return AnyView(NotesPanel(environment: environment, onOpenWindow: openWindow))
      case .agenda: return AnyView(AgendaPanel(environment: environment, onOpenWindow: openWindow))
      case .jira: return AnyView(JiraPanel(environment: environment, onOpenWindow: openWindow))
      case .pulls: return AnyView(GitHubPanel(environment: environment, onOpenWindow: openWindow))
      case .slack: return AnyView(SlackPanel(environment: environment, onOpenWindow: openWindow))
      default: return nil
      }
    }
  }
}
