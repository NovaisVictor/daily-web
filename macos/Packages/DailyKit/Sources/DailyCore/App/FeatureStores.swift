/// One store per module for the whole session, shared by the module's screen
/// (sidebar or its own window) and its panel on Início (spec 011 FR-011-10):
/// moving a panel or switching between grid and tabs must not lose its tab,
/// filters, draft text or scroll position. Cleared on sign-out.
public final class FeatureStores {
  private var stores: [String: AnyObject] = [:]

  public init() {}

  /// The store kept under `key`, created by `make` the first time.
  public func store<Store: AnyObject>(_ key: String, make: () -> Store) -> Store {
    if let existing = stores[key] {
      guard let typed = existing as? Store else {
        // Two features using the same key is a programming error, not a state.
        preconditionFailure("FeatureStores key \(key) holds \(type(of: existing)), not \(Store.self)")
      }
      return typed
    }
    let created = make()
    stores[key] = created
    return created
  }

  public func removeAll() {
    stores.removeAll()
  }
}
