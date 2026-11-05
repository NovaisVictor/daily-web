import DailyCore
import DailyDesign
import SwiftUI

/// The GitHub module as a page or a window of its own: tracked repositories,
/// review requests and your own PRs, with filters, the row actions and
/// "agendar foco" (`components/PullsPanel.tsx`).
public struct PullsScreen: View {
  private let environment: AppEnvironment
  private let store: PullsStore

  public init(environment: AppEnvironment) {
    self.environment = environment
    store = PullsStore.shared(in: environment)
  }

  public var body: some View {
    PullsModuleView(store: store, environment: environment, onOpenWindow: nil)
      .padding(24)
  }
}

#Preview("GitHub") {
  PullsScreen(environment: .preview(state: PullsPreviewData.state))
    .frame(width: 1000, height: 760)
}
