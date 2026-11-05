import DailyCore
import DailyDesign
import SwiftUI

/// The Ferramentas page (`app/(app)/tools/page.tsx`): the header and the integrations.
public struct FerramentasScreen: View {
  private let environment: AppEnvironment

  public init(environment: AppEnvironment) {
    self.environment = environment
  }

  public var body: some View {
    SettingsPageScroll(page: .ferramentas) {
      IntegrationsSettingsView(environment: environment)
    }
  }
}

#Preview {
  FerramentasScreen(environment: .preview())
    .frame(width: 1000, height: 700)
}
