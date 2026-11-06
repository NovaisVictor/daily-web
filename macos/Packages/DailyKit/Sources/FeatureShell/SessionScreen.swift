import DailyCore

/// Which full-window screen the session phase shows. The phase itself is not a
/// good animation key: `.signedIn(user)` changes on every profile edit and
/// `.signedOut(message:)` on every message, and neither is a change of screen.
public enum SessionScreen: Hashable, Sendable {
  case loading
  case restoreFailed
  case login
  case main

  public init(phase: SessionStore.Phase, hasRestoreError: Bool) {
    switch phase {
    case .restoring: self = hasRestoreError ? .restoreFailed : .loading
    case .signedOut: self = .login
    case .signedIn: self = .main
    }
  }
}
