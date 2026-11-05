import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// The Jira module: the four lists, filters, order, watched issues, followed
/// people, the issue actions and the daily summary (`components/JiraPanel.tsx`).
public struct JiraScreen: View {
  @Environment(\.isPrimaryWindow) private var isPrimaryWindow
  private let store: JiraStore
  private let environment: AppEnvironment

  public init(environment: AppEnvironment) {
    self.environment = environment
    store = JiraStore.shared(in: environment)
  }

  /// Only the main window takes the request; it is the one the navigator moved.
  private func revealPending() {
    guard isPrimaryWindow else { return }
    store.revealPending(from: environment.navigator)
  }

  public var body: some View {
    JiraContent(store: store, environment: environment, padding: 24, onOpenWindow: nil)
      .onAppear { revealPending() }
      .onChange(of: environment.navigator.pending) { revealPending() }
      .onChange(of: environment.dashboard.lastUpdated) { revealPending() }
  }
}

extension JiraStore {
  /// The session's one Jira store, shared by the screen and the Início panel
  /// (spec 011 FR-011-10).
  static func shared(in environment: AppEnvironment) -> JiraStore {
    environment.featureStores.store("jira") { JiraStore(environment: environment) }
  }
}

#Preview {
  JiraScreen(environment: .preview(state: JiraPreviewData.state))
    .frame(width: 900, height: 700)
}
