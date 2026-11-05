import DailyCore
import DailyDesign
import SwiftUI

/// How the Configuração page lays out its sections (`app/(app)/config/page.tsx:28`).
enum ConfiguracaoLayout {
  /// The web goes to two columns at `lg` (1024px of viewport, with no sidebar).
  /// Here the width measured is the page's own, beside the sidebar, so the
  /// break is the room both columns need: appearance's button rows and the
  /// layout text side by side.
  static let twoColumnMinWidth: CGFloat = 860
  /// `gap-4`.
  static let spacing: CGFloat = 16
  /// `grid-cols-[minmax(0,1.4fr)_minmax(0,1fr)]`.
  static let leadingFraction: CGFloat = 1.4 / 2.4

  static func columns(forWidth width: CGFloat) -> Int { width >= twoColumnMinWidth ? 2 : 1 }

  /// The two column widths for a page `width` wide.
  static func columnWidths(forWidth width: CGFloat) -> (leading: CGFloat, trailing: CGFloat) {
    let available = max(0, width - spacing)
    let leading = (available * leadingFraction).rounded(.down)
    return (leading, available - leading)
  }
}

/// The Configuração page: Aparência on the left; Disposição, Usuários and the
/// Mac's own settings on the right. One column when narrow.
public struct ConfiguracaoScreen: View {
  private let environment: AppEnvironment
  @State private var width: CGFloat = 0

  public init(environment: AppEnvironment) {
    self.environment = environment
  }

  public var body: some View {
    SettingsPageScroll(page: .configuracao) {
      Group {
        if ConfiguracaoLayout.columns(forWidth: width) == 2 {
          let widths = ConfiguracaoLayout.columnWidths(forWidth: width)
          HStack(alignment: .top, spacing: ConfiguracaoLayout.spacing) {
            appearance.frame(width: widths.leading)
            trailing.frame(width: widths.trailing)
          }
        } else {
          VStack(alignment: .leading, spacing: ConfiguracaoLayout.spacing) {
            appearance
            trailing
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .onGeometryChange(for: CGFloat.self) { proxy in
        proxy.size.width
      } action: { newWidth in
        width = newWidth
      }
    }
  }

  private var appearance: some View {
    AppearanceSettingsView(preferences: environment.preferences)
  }

  private var trailing: some View {
    VStack(alignment: .leading, spacing: ConfiguracaoLayout.spacing) {
      LayoutSettingsView(environment: environment)
      UsersSettingsView(environment: environment)
      MacSettingsView()
    }
  }
}

#Preview {
  ConfiguracaoScreen(environment: .preview())
    .frame(width: 1000, height: 800)
}
