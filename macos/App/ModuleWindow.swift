import DailyCore
import DailyDesign
import FeatureShell
import SwiftUI

/// One module's screen in a window of its own ("Abrir em nova janela"), with the
/// theme and toasts but without the sidebar.
struct ModuleWindow: View {
  let environment: AppEnvironment
  let route: AppRoute?
  let opener: WindowOpener

  var body: some View {
    ThemedRoot(preferences: environment.preferences) {
      content
        .frame(minWidth: 520, minHeight: 420)
        .overlay(alignment: .bottomTrailing) {
          ToastStack(environment.toasts.toasts.map(ToastMessage.init)) { id in
            environment.toasts.dismiss(id)
          }
          .padding(16)
        }
    }
    .navigationTitle(entry?.title ?? "Daily Web")
    .focusedSceneValue(\.shellMenu, menuActions)
    .generalSettingsControls()
  }

  private var registry: ModuleRegistry { .app(environment: environment) }

  /// The route's entry while it is visible for the modules switched on.
  private var entry: ModuleEntry? {
    guard let route else { return nil }
    let enabled = environment.dashboard.state?.modules ?? []
    return registry.visibleEntries(enabled: enabled).first { $0.route == route }
  }

  @ViewBuilder private var content: some View {
    switch environment.session.phase {
    case .signedIn:
      if let entry {
        // Per-route identity, as in the main window's detail: a screen type shared by
        // several routes must not keep another route's @State store.
        entry.makeView()
          .id(entry.route)
      } else {
        ContentUnavailableView(
          "Tela indisponível",
          systemImage: "rectangle.slash",
          description: Text("O módulo desta janela está desligado.")
        )
      }
    case .restoring:
      LoadingState()
    case .signedOut:
      ContentUnavailableView {
        Label("Sessão encerrada", systemImage: "person.crop.circle.badge.xmark")
      } description: {
        Text("Entre pela janela principal.")
      } actions: {
        Button("Entrar…") { opener.showMain(.moduleWindow) }
      }
    }
  }

  /// "Atualizar agora" works here too; "Ir" moves the main window, which owns the
  /// sidebar, and the palette stays there.
  private var menuActions: ShellMenuActions {
    let sidebar = SidebarModel(registry: registry, enabled: environment.dashboard.state?.modules ?? [])
    return ShellMenuActions(
      items: ShellShortcuts.goMenuItems(sidebar),
      selection: nil,
      isRefreshing: environment.dashboard.isRefreshing,
      select: { route in
        environment.navigator.open(route)
        opener.showMain(.moduleWindow)
      },
      openPalette: nil,
      refresh: { Task { await environment.dashboard.refresh() } },
      openInNewWindow: nil
    )
  }
}
