import Observation

/// Which sidebar entry the main window shows. Lives in core so a feature (a
/// toast's "Abrir a nota", a Home card) and a clicked notification can move
/// the window without importing the shell or each other.
@Observable
public final class AppNavigator {
  public var route: AppRoute? = .today
  /// Item the next screen should reveal (a notification's target); the screen
  /// reads it and calls `consumePendingItem()`.
  public private(set) var pendingItemID: String?

  public init() {}

  public func open(_ route: AppRoute, itemID: String? = nil) {
    self.route = route
    pendingItemID = itemID
  }

  public func open(_ target: AlertTarget) {
    open(target.route, itemID: target.itemID)
  }

  /// Returns the pending item once and clears it.
  public func consumePendingItem() -> String? {
    defer { pendingItemID = nil }
    return pendingItemID
  }
}
