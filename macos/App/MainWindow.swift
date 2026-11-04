import DailyCore
import DailyDesign
import DailyModels
import FeatureShell
import SwiftUI

/// The signed-in window: shell, palette and account actions wired to the stores.
struct MainWindow: View {
  let environment: AppEnvironment
  @Bindable var navigator: AppNavigator
  let user: CurrentUser
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    let registry = ModuleRegistry.app(environment: environment)
    let enabled = environment.dashboard.state?.modules ?? []
    ShellRootView(
      registry: registry,
      enabledModules: enabled,
      selection: $navigator.route,
      account: account,
      accountActions: accountActions,
      isRefreshing: environment.dashboard.isRefreshing,
      onRefresh: { Task { await environment.dashboard.refresh() } },
      paletteCommands: paletteCommands(sidebar: SidebarModel(registry: registry, enabled: enabled))
    ) {
      // The notifications bell (T403) goes here.
      EmptyView()
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
      profile: { openSettings() },
      connectAgent: { navigator.open(.access) },
      settings: { openSettings() },
      signOut: { await environment.session.signOut() }
    )
  }

  private func paletteCommands(sidebar: SidebarModel) -> [PaletteCommand] {
    ShellCommands.standard(
      sidebar: sidebar,
      navigate: { navigator.open($0) },
      setTheme: { value in updateAppearance(Appearance(theme: AppearanceTheme(rawValue: value.rawValue))) },
      setDensity: { value in updateAppearance(Appearance(density: AppearanceDensity(rawValue: value.rawValue))) },
      setBackdrop: { value in
        updateAppearance(Appearance(backdrop: AppearanceBackdrop(rawValue: value.rawValue)))
      },
      profile: { openSettings() },
      changePassword: { openSettings() },
      changePhoto: { openSettings() },
      appearance: { openSettings() },
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
