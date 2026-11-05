import DailyCore
import DailyDesign
import SwiftUI

/// The Perfil page (`app/(app)/perfil/page.tsx`), as narrow as the web's `max-w-lg`.
public struct PerfilScreen: View {
  /// `max-w-lg`, 32rem.
  static let maxContentWidth: CGFloat = 512
  private let environment: AppEnvironment

  public init(environment: AppEnvironment) {
    self.environment = environment
  }

  public var body: some View {
    SettingsPageScroll(page: .perfil, maxContentWidth: Self.maxContentWidth) {
      ProfileSettingsView(environment: environment)
    }
  }
}

#Preview {
  PerfilScreen(environment: .preview())
    .frame(width: 800, height: 800)
}
