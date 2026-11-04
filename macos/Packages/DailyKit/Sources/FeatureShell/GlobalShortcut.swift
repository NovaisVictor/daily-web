import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
  /// "Abrir Daily Web", ⌃⌥⌘D until the user records another one. Not ⌥⌘D:
  /// that is the system's "Turn Dock hiding on/off", so every Dock toggle
  /// brought the app forward, hidden or not (G-14).
  static let openDailyWeb = Self("openDailyWeb", initial: .init(.d, modifiers: [.control, .option, .command]))
}

/// The system-wide shortcut that brings the app forward from anywhere.
public enum GlobalShortcut {
  /// Call once at launch; `action` runs on every key up while the shortcut is set.
  public static func install(action: @escaping () -> Void) {
    KeyboardShortcuts.onKeyUp(for: .openDailyWeb, action: action)
  }
}

/// Records the global shortcut; the library stores it in `UserDefaults`.
public struct GlobalShortcutRecorder: View {
  public init() {}

  public var body: some View {
    KeyboardShortcuts.Recorder("Abrir Daily Web", name: .openDailyWeb)
  }
}
