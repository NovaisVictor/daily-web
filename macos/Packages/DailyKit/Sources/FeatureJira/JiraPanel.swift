import DailyCore
import DailyDesign
import SwiftUI

/// The Jira panel of Início (spec 011 FR-011-06, `components/JiraPanel.tsx:626-1070`):
/// the same module as `JiraScreen`, over the same store, without its own frame;
/// the host puts it on the panel surface.
public struct JiraPanel: View {
  private let store: JiraStore
  private let environment: AppEnvironment
  private let onOpenWindow: (() -> Void)?

  public init(environment: AppEnvironment) {
    self.init(environment: environment, onOpenWindow: nil)
  }

  /// `onOpenWindow` adds "Abrir em nova janela" to the header's "…" menu.
  public init(environment: AppEnvironment, onOpenWindow: (() -> Void)?) {
    self.environment = environment
    self.onOpenWindow = onOpenWindow
    store = JiraStore.shared(in: environment)
  }

  public var body: some View {
    JiraContent(store: store, environment: environment, padding: 0, onOpenWindow: onOpenWindow)
  }
}

#Preview("Painel estreito") {
  JiraPanel(environment: .preview(state: JiraPreviewData.state), onOpenWindow: {})
    .padding(18)
    .frame(width: 420, height: 640)
    .glassSurface(.panel)
}

#Preview("Painel largo") {
  JiraPanel(environment: .preview(state: JiraPreviewData.state), onOpenWindow: {})
    .padding(18)
    .frame(width: 700, height: 640)
    .glassSurface(.panel)
}
