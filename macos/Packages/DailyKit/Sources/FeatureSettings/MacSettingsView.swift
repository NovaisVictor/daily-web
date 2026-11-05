import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

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
  /// Set by the app on its windows, for the Mac section of Configuração; nil in previews.
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
