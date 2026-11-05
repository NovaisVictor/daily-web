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

  /// The saved arrangement is the web's grid; the native Início keeps a fixed layout
  /// until spec 010, so the text only promises what restoring does today.
  // TODO(spec 010): once the native grid can be arranged, go back to the hold-to-arrange
  // instruction ("No Início, segure um painel por meio segundo para movê-lo arrastando e
  // redimensioná-lo pelo canto…", FR-010-02/03 and FR-010-11) and add
  // "(ou use Visualizar → Organizar painéis)" once that menu item exists.
  static let explanation =
    "A disposição dos painéis é a da grade do Início no navegador; este app ainda usa uma "
    + "disposição fixa. Restaurar volta a grade do navegador ao padrão."

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
