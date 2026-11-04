import DailyCore
import SwiftUI

/// The window-level shortcuts: ⌘K opens the palette, ⌘R refreshes, ⌘1…⌘9 jump to
/// the sidebar rows in order.
public enum ShellShortcuts {
  /// One digit per route, for the first nine routes.
  public static func routeShortcuts(_ routes: [AppRoute]) -> [(key: Character, route: AppRoute)] {
    zip(1...9, routes).map { (key: Character(String($0)), route: $1) }
  }
}

extension View {
  /// Installs the shell's shortcuts on this view's window. `ShellRootView` applies it
  /// itself; it is public so another window can offer the same keys.
  public func shellKeyboardShortcuts(
    routes: [AppRoute],
    onOpenPalette: @escaping () -> Void,
    onRefresh: @escaping () -> Void,
    onSelect: @escaping (AppRoute) -> Void
  ) -> some View {
    background {
      ShellShortcutButtons(
        routes: routes,
        onOpenPalette: onOpenPalette,
        onRefresh: onRefresh,
        onSelect: onSelect
      )
    }
  }
}

/// Invisible buttons carry the shortcuts because a key equivalent only exists on a
/// control; they take no space and stay out of the accessibility tree, where the
/// visible toolbar buttons already describe the same actions.
private struct ShellShortcutButtons: View {
  let routes: [AppRoute]
  let onOpenPalette: () -> Void
  let onRefresh: () -> Void
  let onSelect: (AppRoute) -> Void

  var body: some View {
    ZStack {
      Button("Buscar", action: onOpenPalette).keyboardShortcut("k", modifiers: .command)
      Button("Atualizar agora", action: onRefresh).keyboardShortcut("r", modifiers: .command)
      ForEach(ShellShortcuts.routeShortcuts(routes), id: \.route) { shortcut in
        Button(String(shortcut.key)) { onSelect(shortcut.route) }
          .keyboardShortcut(KeyEquivalent(shortcut.key), modifiers: .command)
      }
    }
    .frame(width: 0, height: 0)
    .opacity(0)
    .accessibilityHidden(true)
  }
}
