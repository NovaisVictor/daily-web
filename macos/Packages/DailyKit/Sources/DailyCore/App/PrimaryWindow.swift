import SwiftUI

extension EnvironmentValues {
  /// True only in the main window, the one that follows `AppNavigator`.
  /// Navigator requests (a pending item, "Abrir notificações") target that
  /// window; a module window or an extra ⌘N window showing the same screen
  /// must not consume them first. False by default, so a window that forgets
  /// to say otherwise never steals a request.
  @Entry public var isPrimaryWindow = false
}
