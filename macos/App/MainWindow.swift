import DailyCore
import DailyDesign
import DailyModels
import FeatureNotifications
import FeatureShell
import SwiftUI

/// The signed-in window: shell, palette and account actions wired to the stores.
struct MainWindow: View {
  let environment: AppEnvironment
  @Binding var selection: AppRoute?
  let user: CurrentUser
  let opener: WindowOpener

  var body: some View {
    let registry = ModuleRegistry.app(environment: environment)
    let enabled = environment.dashboard.state?.modules ?? []
    ShellRootView(
      registry: registry,
      enabledModules: enabled,
      selection: $selection,
      account: account,
      appearance: appearance,
      accountActions: accountActions,
      isRefreshing: environment.dashboard.isRefreshing,
      onRefresh: { Task { await environment.dashboard.refresh() } },
      paletteCommands: paletteCommands(sidebar: SidebarModel(registry: registry, enabled: enabled)),
      onOpenInNewWindow: { opener.open($0) }
    ) {
      NotificationsBell(environment: environment)
    }
    .environment(\.modulePanels, .app(environment: environment, opener: opener))
  }

  private var account: ShellAccount {
    ShellAccount(
      displayName: user.fullName ?? user.username,
      username: user.username,
      avatar: user.avatarUrl.flatMap(DataURL.decode)
    )
  }

  private var appearance: ShellAppearance {
    let current = DesignAppearance(environment.preferences.appearance)
    return ShellAppearance(theme: current.theme, density: current.density, backdrop: current.backdrop)
  }

  /// Perfil and Configuração are pages of this window now (spec 012 FR-012-05).
  private var accountActions: ShellAccountActions {
    ShellAccountActions(
      profile: { selection = .perfil },
      connectAgent: { selection = .access },
      agentsWorkspace: { selection = .agents },
      settings: { selection = .configuracao },
      setTheme: setTheme,
      setDensity: setDensity,
      setBackdrop: setBackdrop,
      signOut: { await environment.session.signOut() }
    )
  }

  private func setTheme(_ value: ThemePreference) {
    updateAppearance(Appearance(theme: AppearanceTheme(rawValue: value.rawValue)))
  }

  private func setDensity(_ value: Density) {
    updateAppearance(Appearance(density: AppearanceDensity(rawValue: value.rawValue)))
  }

  private func setBackdrop(_ value: Backdrop) {
    updateAppearance(Appearance(backdrop: AppearanceBackdrop(rawValue: value.rawValue)))
  }

  private func paletteCommands(sidebar: SidebarModel) -> [PaletteCommand] {
    ShellCommands.standard(
      sidebar: sidebar,
      navigate: { selection = $0 },
      setTheme: setTheme,
      setDensity: setDensity,
      setBackdrop: setBackdrop,
      profile: { selection = .perfil },
      changePassword: { selection = .perfil },
      changePhoto: { selection = .perfil },
      appearance: { selection = .configuracao },
      signOut: { Task { await environment.session.signOut() } }
    )
  }

  private func updateAppearance(_ patch: Appearance) {
    // The store reverts and shows a toast on failure; nothing else to do here.
    Task { _ = await environment.preferences.updateAppearance(patch) }
  }
}

/// Avatars arrive as `data:image/...;base64,...` (`app/api/me/avatar/route.ts:8`).
enum DataURL {
  static func decode(_ url: String) -> Data? {
    guard url.hasPrefix("data:"), let comma = url.firstIndex(of: ",") else { return nil }
    return Data(base64Encoded: String(url[url.index(after: comma)...]))
  }
}
