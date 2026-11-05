import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// The agenda module as a full screen (sidebar or its own window). It shares
/// its store with `AgendaPanel`.
public struct AgendaScreen: View {
  private let store: AgendaStore
  private let session: SessionStore

  public init(environment: AppEnvironment) {
    session = environment.session
    store = AgendaStore.shared(in: environment)
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        SectionHeader("Agenda")
        AgendaContent(store: store, server: session.serverURL)
      }
      .padding(24)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

#Preview {
  AgendaScreen(environment: .preview())
    .frame(width: 560, height: 520)
}
