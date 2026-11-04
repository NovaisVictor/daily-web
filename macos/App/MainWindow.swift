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
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    let registry = ModuleRegistry.app(environment: environment)
    let enabled = environment.dashboard.state?.modules ?? []
    ShellRootView(
      registry: registry,
      enabledModules: enabled,
      selection: $selection,
      account: account,
      accountActions: accountActions,
      isRefreshing: environment.dashboard.isRefreshing,
      onRefresh: { Task { await environment.dashboard.refresh() } },
      paletteCommands: paletteCommands(sidebar: SidebarModel(registry: registry, enabled: enabled)),
      onOpenInNewWindow: { opener.open($0) }
    ) {
      NotificationsBell(environment: environment)
    }
  }

  private var account: ShellAccount {
    ShellAccount(
      displayName: user.fullName ?? user.username,
      username: user.username,
      avatar: user.avatarUrl.flatMap(DataURL.decode)
    )
  }

  private var accountActions: ShellAccountActions {
    ShellAccountActions(
      profile: { showSettings(.profile) },
      connectAgent: { selection = .access },
      settings: { openSettings() },
      signOut: { await environment.session.signOut() }
    )
  }

  private func paletteCommands(sidebar: SidebarModel) -> [PaletteCommand] {
    ShellCommands.standard(
      sidebar: sidebar,
      navigate: { selection = $0 },
      setTheme: { value in updateAppearance(Appearance(theme: AppearanceTheme(rawValue: value.rawValue))) },
      setDensity: { value in updateAppearance(Appearance(density: AppearanceDensity(rawValue: value.rawValue))) },
      setBackdrop: { value in
        updateAppearance(Appearance(backdrop: AppearanceBackdrop(rawValue: value.rawValue)))
      },
      profile: { showSettings(.profile) },
      changePassword: { showSettings(.profile) },
      changePhoto: { showSettings(.profile) },
      appearance: { showSettings(.appearance) },
      signOut: { Task { await environment.session.signOut() } }
    )
  }

  /// Settings on `tab`; the Settings screen reads the request even when it is already open.
  private func showSettings(_ tab: SettingsDestination) {
    environment.navigator.requestSettings(tab)
    openSettings()
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
