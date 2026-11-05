import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// The tasks panel of Início (`TasksPanel.tsx:395`): the whole module, list and
/// board, inside a panel. It draws no frame of its own; the host puts it on the
/// panel surface. It shares its store with `TasksScreen`.
public struct TasksPanel: View {
  private let environment: AppEnvironment
  private let store: TasksStore
  private let onOpenWindow: (() -> Void)?

  public init(environment: AppEnvironment) {
    self.init(environment: environment, onOpenWindow: nil)
  }

  /// `onOpenWindow` adds "Abrir em nova janela" to the header's "…" menu (FR-011-01).
  public init(environment: AppEnvironment, onOpenWindow: (() -> Void)?) {
    self.environment = environment
    store = TasksStore.shared(in: environment)
    self.onOpenWindow = onOpenWindow
  }

  public var body: some View {
    TasksContent(environment: environment, store: store, isPanel: true, onOpenWindow: onOpenWindow)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

#Preview("Painel 420pt") {
  TasksPanel(environment: .preview(state: TasksPreviewData.state), onOpenWindow: {})
    .padding(16)
    .frame(width: 420, height: 640)
}

#Preview("Painel 700pt") {
  TasksPanel(environment: .preview(state: TasksPreviewData.listState))
    .padding(16)
    .frame(width: 700, height: 640)
}
