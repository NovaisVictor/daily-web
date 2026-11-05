import DailyCore
import DailyDesign
import SwiftUI

/// The three pages the web splits settings into (`app/(app)/tools`, `config`
/// and `perfil`). The navigation maps each to its `AppRoute`.
public enum SettingsPage: String, CaseIterable, Hashable, Sendable {
  case ferramentas, configuracao, perfil

  /// Where an old Settings tab request lands now: the integrations moved to
  /// Ferramentas, the profile to Perfil, and the rest lives in Configuração.
  public init(_ destination: SettingsDestination) {
    switch destination {
    case .integrations: self = .ferramentas
    case .profile: self = .perfil
    case .appearance, .users, .general: self = .configuracao
    }
  }

  /// The page title (`PageHeader title`).
  public var title: String {
    switch self {
    case .ferramentas: "Ferramentas"
    case .configuracao: "Configuração"
    case .perfil: "Perfil"
    }
  }

  /// The page description, where the web has one.
  public var description: String? {
    switch self {
    case .ferramentas: nil
    case .configuracao: "Ajuste a aparência, a disposição dos painéis e quem tem acesso."
    case .perfil: "Sua foto, seus dados e sua senha."
    }
  }
}

/// `components/data/PageHeader.tsx`: `type-heading` title and an ink-mid line under it.
struct PageHeader: View {
  @Environment(\.theme) private var theme
  let page: SettingsPage

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(page.title)
        .typeRole(.heading)
        .foregroundStyle(theme.ink)
        .accessibilityAddTraits(.isHeader)
      if let description = page.description {
        Text(description)
          .typeRole(.data)
          .foregroundStyle(theme.inkMid)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.bottom, 12)
  }
}

/// The scrolling page shell: header, then the content, with the web's `gap-4`.
struct SettingsPageScroll<Content: View>: View {
  let page: SettingsPage
  /// `max-w-lg` on the profile page; nil fills the width.
  var maxContentWidth: CGFloat?
  @ViewBuilder let content: Content

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        PageHeader(page: page)
        content
          .frame(maxWidth: maxContentWidth ?? .infinity, alignment: .leading)
      }
      .padding(24)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

/// `components/ui/Section.tsx` over `Panel`: one glass card per topic, `gap-5 p-6`.
struct SettingsSection<Content: View, Actions: View>: View {
  let title: String
  var count: String?
  @ViewBuilder let content: Content
  @ViewBuilder let actions: Actions

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      SectionHeader(title, count: count) { actions }
      content
    }
    .padding(24)
    .frame(maxWidth: .infinity, alignment: .leading)
    .glassSurface(.panel)
  }
}

extension SettingsSection where Actions == EmptyView {
  init(_ title: String, count: String? = nil, @ViewBuilder content: () -> Content) {
    self.title = title
    self.count = count
    self.content = content()
    self.actions = EmptyView()
  }
}
