import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// The agenda panel of Início (`components/AgendaPanel.tsx:111-175`): header,
/// drop zone, period chips and the days. It draws no frame of its own; the host
/// puts it on the panel surface. It shares its store with `AgendaScreen`.
public struct AgendaPanel: View {
  private let store: AgendaStore
  private let session: SessionStore
  private let onOpenWindow: (() -> Void)?

  public init(environment: AppEnvironment) {
    self.init(environment: environment, onOpenWindow: nil)
  }

  /// `onOpenWindow` adds "Abrir em nova janela" to the header's "…" menu (FR-011-01).
  public init(environment: AppEnvironment, onOpenWindow: (() -> Void)?) {
    session = environment.session
    store = AgendaStore.shared(in: environment)
    self.onOpenWindow = onOpenWindow
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      SectionHeader("Agenda") {
        if let onOpenWindow {
          IconMenu("Mais ações", systemImage: "ellipsis", size: .small) {
            Button("Abrir em nova janela", action: onOpenWindow)
          }
        }
      }
      ScrollView {
        AgendaContent(store: store, server: session.serverURL)
      }
      .scrollIndicators(.automatic)
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }
}

#Preview("Painel 420pt") {
  AgendaPanel(environment: .preview(), onOpenWindow: {})
    .padding(16)
    .frame(width: 420, height: 480)
}

#Preview("Painel 700pt") {
  AgendaPanel(environment: .preview())
    .padding(16)
    .frame(width: 700, height: 480)
}
