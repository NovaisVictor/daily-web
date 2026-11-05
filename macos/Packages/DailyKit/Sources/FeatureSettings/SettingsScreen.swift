import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// The old tabs of the Settings scene, kept for callers that still name one;
/// each now opens a `SettingsPage`.
public enum SettingsTab: String, CaseIterable, Hashable, Sendable {
  case appearance, integrations, profile, users, general

  /// The core request mirrored one to one.
  public init(_ destination: SettingsDestination) {
    switch destination {
    case .appearance: self = .appearance
    case .integrations: self = .integrations
    case .profile: self = .profile
    case .users: self = .users
    case .general: self = .general
    }
  }

  var destination: SettingsDestination {
    switch self {
    case .appearance: .appearance
    case .integrations: .integrations
    case .profile: .profile
    case .users: .users
    case .general: .general
    }
  }
}

/// The Settings scene (⌘,) until the navigation opens the pages in the main
/// window: the three pages that replaced the old tabs, with a switch between them.
public struct SettingsScreen: View {
  private let environment: AppEnvironment
  @State private var page: SettingsPage

  public init(environment: AppEnvironment) {
    self.init(environment: environment, initialTab: .appearance)
  }

  public init(environment: AppEnvironment, initialTab: SettingsTab) {
    self.environment = environment
    _page = State(initialValue: SettingsPage(initialTab.destination))
  }

  public var body: some View {
    VStack(spacing: 0) {
      SegmentedPills(
        "Página",
        items: [SettingsPage.configuracao, .ferramentas, .perfil].map { .init(id: $0, label: $0.title) },
        selection: $page
      )
      .padding(.top, 16)
      switch page {
      case .ferramentas: FerramentasScreen(environment: environment)
      case .configuracao: ConfiguracaoScreen(environment: environment)
      case .perfil: PerfilScreen(environment: environment)
      }
    }
    .frame(minWidth: 720, idealWidth: 960, minHeight: 520, idealHeight: 720)
    // The request arrives before the window opens (onAppear) or while it is
    // already open (onChange).
    .onAppear(perform: takeRequestedPage)
    .onChange(of: environment.navigator.requestedSettingsTab) { takeRequestedPage() }
  }

  private func takeRequestedPage() {
    guard let tab = environment.navigator.takeRequestedSettingsTab() else { return }
    page = SettingsPage(tab)
  }
}

/// The controls of the Mac section of Configuração. They come from the app, which owns the
/// global shortcut library and the login item; a feature cannot import the shell.
public struct GeneralSettingsControls {
  public let shortcutRecorder: AnyView
  public let launchAtLogin: AnyView

  public init(shortcutRecorder: some View, launchAtLogin: some View) {
    self.shortcutRecorder = AnyView(shortcutRecorder)
    self.launchAtLogin = AnyView(launchAtLogin)
  }
}

extension EnvironmentValues {
  /// Set by the app on the Settings scene; nil in previews.
  @Entry public var generalSettingsControls: GeneralSettingsControls?
}

/// The Mac's own settings, the old "Geral" tab: global shortcut and launch at
/// login. The web has no counterpart, so the section is native only.
struct MacSettingsView: View {
  @Environment(\.generalSettingsControls) private var controls
  @Environment(\.theme) private var theme

  var body: some View {
    SettingsSection("Mac") {
      item("Atalho global") { controls?.shortcutRecorder }
      item("Abrir ao iniciar") { controls?.launchAtLogin }
    }
  }

  private func item(_ title: String, @ViewBuilder control: () -> AnyView?) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .typeRole(.caption)
        .foregroundStyle(theme.inkDim)
        .accessibilityAddTraits(.isHeader)
      if let view = control() {
        view
      } else {
        Text("Disponível só no app.")
          .typeRole(.data)
          .foregroundStyle(theme.inkDim)
      }
    }
  }
}

#Preview {
  SettingsScreen(environment: .preview())
}
