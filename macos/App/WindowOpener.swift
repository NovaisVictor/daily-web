import AppKit
import DailyCore
import SwiftUI
import os

/// Brings the main window forward from places without SwiftUI's environment: the
/// app delegate (Dock click, notification click) and the global shortcut.
@Observable
final class WindowOpener {
  /// Captured from the first view that renders; every scene's action opens windows
  /// of the whole app.
  @ObservationIgnored var openWindow: OpenWindowAction?

  private static let logger = Logger(subsystem: "io.github.novaisvictor.dailyweb", category: "App")

  /// Why the app comes forward. Only explicit user actions may activate it
  /// (G-14); the reason goes to the log so an unexpected activation can be traced.
  enum Reason: String {
    case dock, globalShortcut, menuBar, notification, moduleWindow
  }

  /// Activates the app and shows the main window, reopening it when it was closed.
  func showMain(_ reason: Reason) {
    Self.logger.notice("Showing the main window: \(reason.rawValue, privacy: .public)")
    NSApp.activate()
    guard let openWindow else {
      // Only before any scene rendered, i.e. during launch, when the main window is
      // about to appear anyway.
      Self.logger.error("No window opener yet; the main window cannot be shown")
      return
    }
    openWindow(id: SceneID.main)
  }

  /// "Abrir em nova janela", always from a click or a menu command.
  func open(_ route: AppRoute) {
    NSApp.activate()
    guard let openWindow else {
      Self.logger.error("No window opener yet; the module window cannot be opened")
      return
    }
    openWindow(id: SceneID.module, value: WindowRoute(route))
  }
}

/// Hands the scene's `openWindow` to the opener once the view appears.
struct CapturesWindowOpener: ViewModifier {
  let opener: WindowOpener
  @Environment(\.openWindow) private var openWindow

  func body(content: Content) -> some View {
    content.onAppear { opener.openWindow = openWindow }
  }
}
