import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// "Disposição dos painéis" (`components/LayoutPanel.tsx`). The restore lives
/// here and not on the Home screen because it is a rare action.
struct LayoutSettingsView: View {
  @Environment(\.theme) private var theme
  @State private var store: LayoutStore
  private let dashboard: DashboardStore

  init(environment: AppEnvironment) {
    let dashboard = environment.dashboard
    self.dashboard = dashboard
    _store = State(initialValue: LayoutStore(client: environment.client) { await dashboard.reload() })
  }

  init(store: LayoutStore, dashboard: DashboardStore) {
    _store = State(initialValue: store)
    self.dashboard = dashboard
  }

  /// The web tells you to click "Organizar" and "Concluir", which the grid
  /// never had; this follows how the native grid is arranged (spec 010
  /// FR-010-02/03 and FR-010-11).
  static let explanation =
    "No Início, segure um painel por meio segundo (ou use Visualizar → Organizar painéis) para "
    + "movê-lo arrastando e redimensioná-lo pelo canto. Salvar guarda a disposição para o tamanho "
    + "da janela."

  var body: some View {
    SettingsSection("Disposição dos painéis") {
      Text(Self.explanation)
        .typeRole(.data)
        .foregroundStyle(theme.inkMid)
        .frame(maxWidth: 520, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
      if let error = store.error { PanelError(error) }
      switch store.status(current: dashboard.state?.layout) {
      case .isDefault:
        Text("Os painéis estão na disposição padrão.")
          .typeRole(.caption)
          .foregroundStyle(theme.inkDim)
          .padding(.vertical, 24)
      case .customized:
        Button(store.isRestoring ? "Restaurando…" : "Restaurar disposição padrão") {
          Task { await store.restore() }
        }
        .pillButtonStyle(.outline, size: .small)
        .disabled(store.isRestoring)
      case .unknown:
        EmptyView()
      }
    }
    .task { await store.load() }
  }
}
