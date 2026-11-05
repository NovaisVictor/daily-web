import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// "Disposição dos painéis" (`components/LayoutPanel.tsx`). The restore lives
/// here and not on the Home screen because it is a rare action.
struct LayoutSettingsView: View {
  @Environment(\.theme) private var theme
  /// The session's arrangement store, the one Início saves through, so a
  /// layout saved for some window size shows here as a change at once.
  private let store: DashboardLayoutStore

  init(environment: AppEnvironment) {
    store = DashboardLayoutStore.shared(in: environment)
  }

  /// Spec 010 FR-010-02/03 and FR-010-11. The web's own copy names "Organizar" and
  /// "Concluir" buttons that its grid never renders, so this follows what the grid does.
  static let explanation =
    "No Início, segure um painel por meio segundo (ou use Visualizar → Organizar painéis) "
    + "para movê-lo arrastando e redimensioná-lo pelo canto. Salvar guarda a disposição para o "
    + "tamanho da janela, e ela vale também no navegador. Restaurar volta a grade ao padrão."

  var body: some View {
    SettingsSection("Disposição dos painéis") {
      Text(Self.explanation)
        .typeRole(.data)
        .foregroundStyle(theme.inkMid)
        .frame(maxWidth: 520, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
      if let error = store.checkError ?? store.resetError { PanelError(error) }
      switch store.isDefaultGrid {
      case .some(true):
        Text("Os painéis estão na disposição padrão.")
          .typeRole(.caption)
          .foregroundStyle(theme.inkDim)
          .padding(.vertical, 24)
      case .some(false):
        Button(store.isResettingGrid ? "Restaurando…" : "Restaurar disposição padrão") {
          Task { await store.resetGrid() }
        }
        .pillButtonStyle(.outline, size: .small)
        .disabled(store.isResettingGrid)
      case .none:
        EmptyView()
      }
    }
    .task { await store.checkDefaultGrid() }
  }
}
