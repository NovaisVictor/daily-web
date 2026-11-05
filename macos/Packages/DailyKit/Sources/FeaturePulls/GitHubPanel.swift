import DailyCore
import DailyDesign
import SwiftUI

/// The GitHub panel of Início (`components/PullsPanel.tsx:280-391`, spec 011
/// FR-011-07): the whole module, without a frame of its own; the host puts it
/// on the panel surface. Shares its store with `PullsScreen`.
public struct GitHubPanel: View {
  private let environment: AppEnvironment
  private let store: PullsStore
  private let onOpenWindow: (() -> Void)?

  public init(environment: AppEnvironment) {
    self.init(environment: environment, onOpenWindow: nil)
  }

  /// With `onOpenWindow`, the header's "…" offers "Abrir em nova janela".
  public init(environment: AppEnvironment, onOpenWindow: (() -> Void)?) {
    self.environment = environment
    self.onOpenWindow = onOpenWindow
    store = PullsStore.shared(in: environment)
  }

  public var body: some View {
    PullsModuleView(store: store, environment: environment, onOpenWindow: onOpenWindow)
  }
}

#Preview("GitHub · 420pt") {
  GitHubPanel(environment: .preview(state: PullsPreviewData.state), onOpenWindow: {})
    .padding(16)
    .glassSurface(.panel)
    .frame(width: 420, height: 640)
    .padding()
}

#Preview("GitHub · 700pt") {
  GitHubPanel(environment: .preview(state: PullsPreviewData.state), onOpenWindow: {})
    .padding(16)
    .glassSurface(.panel)
    .frame(width: 700, height: 640)
    .padding()
}
