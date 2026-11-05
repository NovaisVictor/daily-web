import DailyCore
import SwiftUI

/// ⌘1…⌘9 jump to the pages and then the modules, in sidebar order (FR-012-07).
public enum ShellShortcuts {
  /// One digit per route, for the first nine routes.
  public static func routeShortcuts(_ routes: [AppRoute]) -> [(key: Character, route: AppRoute)] {
    zip(1...9, routes).map { (key: Character(String($0)), route: $1) }
  }

  /// The "Ir" menu: every sidebar row, top to bottom; the pages and modules carry their
  /// digit while there are digits left, the "Ajustes" rows never do.
  public static func goMenuItems(_ sidebar: SidebarModel) -> [ShellMenuItem] {
    let numbered = routeShortcuts(sidebar.numberedEntries.map(\.route))
    let keys = Dictionary(uniqueKeysWithValues: numbered.map { ($0.route, $0.key) })
    return sidebar.orderedEntries.map { entry in
      ShellMenuItem(route: entry.route, title: entry.title, systemImage: entry.systemImage, key: keys[entry.route])
    }
  }
}

/// One row of the "Ir" menu.
public struct ShellMenuItem: Equatable, Identifiable, Sendable {
  public let route: AppRoute
  public let title: String
  public let systemImage: String
  /// The digit pressed with ⌘; nil past the ninth row.
  public let key: Character?

  public var id: AppRoute { route }
}

/// What the focused shell window offers the menu bar's commands. Published per
/// window with `focusedSceneValue`, so the menus act on the window in front.
public struct ShellMenuActions {
  public let items: [ShellMenuItem]
  public let selection: AppRoute?
  public let isRefreshing: Bool
  public let select: (AppRoute) -> Void
  /// Nil in a window without the palette (a single module's window).
  public let openPalette: (() -> Void)?
  public let refresh: () -> Void
  /// Nil when the app offers no extra windows.
  public let openInNewWindow: ((AppRoute) -> Void)?

  public init(
    items: [ShellMenuItem],
    selection: AppRoute?,
    isRefreshing: Bool,
    select: @escaping (AppRoute) -> Void,
    openPalette: (() -> Void)?,
    refresh: @escaping () -> Void,
    openInNewWindow: ((AppRoute) -> Void)?
  ) {
    self.items = items
    self.selection = selection
    self.isRefreshing = isRefreshing
    self.select = select
    self.openPalette = openPalette
    self.refresh = refresh
    self.openInNewWindow = openInNewWindow
  }
}

extension FocusedValues {
  @Entry public var shellMenu: ShellMenuActions?
}

/// The shell's menu bar commands: "Ir" with ⌘K and ⌘1…⌘9, "Atualizar agora" (⌘R) in
/// the View menu and "Abrir em nova janela" in the File menu. Real menu items, so the
/// keys show in the menu bar instead of living on hidden buttons.
public struct ShellMenuCommands: Commands {
  @FocusedValue(\.shellMenu) private var shell

  public init() {}

  public var body: some Commands {
    CommandGroup(after: .newItem) {
      Button("Abrir em nova janela") {
        if let shell, let route = shell.selection { shell.openInNewWindow?(route) }
      }
      .keyboardShortcut("n", modifiers: [.command, .shift])
      .disabled(shell?.selection == nil || shell?.openInNewWindow == nil)
    }
    CommandGroup(before: .toolbar) {
      Button("Atualizar agora") { shell?.refresh() }
        .keyboardShortcut("r", modifiers: .command)
        .disabled(shell == nil || shell?.isRefreshing == true)
      Divider()
    }
    CommandMenu("Ir") {
      Button("Buscar…") { shell?.openPalette?() }
        .keyboardShortcut("k", modifiers: .command)
        .disabled(shell?.openPalette == nil)
      Divider()
      ForEach(shell?.items ?? []) { item in
        goButton(item)
      }
    }
  }

  @ViewBuilder private func goButton(_ item: ShellMenuItem) -> some View {
    let button = Button(item.title, systemImage: item.systemImage) { shell?.select(item.route) }
    if let key = item.key {
      button.keyboardShortcut(KeyEquivalent(key), modifiers: .command)
    } else {
      button
    }
  }
}
