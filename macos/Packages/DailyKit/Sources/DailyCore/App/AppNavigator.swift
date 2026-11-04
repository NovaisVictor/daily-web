import Observation

/// Which sidebar entry the main window shows. Lives in core so a feature (a
/// toast's "Abrir a nota", a Home card) and a clicked notification can move
/// the window without importing the shell or each other.
@Observable
public final class AppNavigator {
  /// An item some screen should reveal, tied to the route that owns it so it
  /// never leaks into another screen.
  public struct PendingItem: Equatable, Sendable {
    public let route: AppRoute
    public let itemID: String
  }

  /// Bound to the sidebar. Choosing another entry there drops a pending item
  /// meant for a different screen.
  public var route: AppRoute? = .today {
    didSet {
      if let pending, pending.route != route { self.pending = nil }
    }
  }

  public private(set) var pending: PendingItem?

  public init() {}

  public func open(_ route: AppRoute, itemID: String? = nil) {
    pending = itemID.map { PendingItem(route: route, itemID: $0) }
    self.route = route
  }

  public func open(_ target: AlertTarget) {
    open(target.route, itemID: target.itemID)
  }

  /// The item waiting for `route`, without clearing it. Screens read it,
  /// observe it (`onChange`), and call `finishPendingItem` once the item was
  /// found in their data, or could never be found (data loaded without it).
  public func pendingItem(for route: AppRoute) -> String? {
    guard let pending, pending.route == route else { return nil }
    return pending.itemID
  }

  /// Clears the pending item if it is still `itemID` for `route`.
  public func finishPendingItem(_ itemID: String, for route: AppRoute) {
    guard pending == PendingItem(route: route, itemID: itemID) else { return }
    pending = nil
  }
}
