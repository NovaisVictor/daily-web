import Foundation
import os

/// What each panel remembers between launches: what the web keeps in the URL
/// (open folder, open message, search, tab). Spec 015 FR-015-01.
///
/// Kept per account (server origin and username), as the appearance mirror of
/// `PreferencesStore`: two accounts never see each other's folder or search,
/// and a sign-out leaves the account's values for its next sign-in.
public final class ViewStateStore {
  /// Prefix of every `UserDefaults` key written here.
  public static let keyPrefix = "io.github.novaisvictor.dailyweb.viewState"
  /// `UserDefaults` key naming the account signed in last, so the stores a
  /// window builds at launch restore before the session is checked.
  static let lastAccountKey = "io.github.novaisvictor.dailyweb.viewStateAccount"

  private struct Observer {
    weak var owner: AnyObject?
    let restore: () -> Void
  }

  private let defaults: UserDefaults
  private let scope: AccountScope
  /// The key prefix of the signed-in account; nil reads nothing and writes nothing.
  private var account: String?
  private var observers: [Observer] = []

  public init(defaults: UserDefaults) {
    self.defaults = defaults
    let scope = AccountScope(prefix: Self.keyPrefix, lastAccountKey: Self.lastAccountKey, defaults: defaults)
    self.scope = scope
    account = scope.lastAccount
  }

  /// Whether an account is active, so reads and writes reach the disk.
  public var isActive: Bool { account != nil }

  /// Switches to the values of the account that just signed in. When that is
  /// another account than the one read so far, the stores observing read their
  /// values again.
  public func activate(server: URL, username: String) {
    guard let key = scope.activate(server: server, username: username) else {
      Logger.core.error("No remembered view state for a server without an http(s) origin")
      deactivate()
      return
    }
    guard key != account else { return }
    account = key
    observers.removeAll { $0.owner == nil }
    for observer in observers { observer.restore() }
  }

  /// Signed out: nothing is read or written until the next sign-in. The
  /// account's values stay on disk for it.
  public func deactivate() {
    account = nil
    scope.deactivate()
  }

  /// Calls `restore` each time a sign-in switches accounts, for as long as
  /// `owner` lives. A store built while the session was still being checked
  /// read the last account's values, or none; this gives it the right ones.
  public func observe(_ owner: AnyObject, restore: @escaping () -> Void) {
    observers.removeAll { $0.owner == nil }
    observers.append(Observer(owner: owner, restore: restore))
  }

  public func string(module: String, field: String) -> String? {
    guard let key = key(module, field) else { return nil }
    return defaults.string(forKey: key)
  }

  /// nil when never written, so a stored `false` differs from "no value".
  public func bool(module: String, field: String) -> Bool? {
    guard let key = key(module, field), defaults.object(forKey: key) != nil else { return nil }
    return defaults.bool(forKey: key)
  }

  /// A remembered enum, such as a tab; nil when never written or no longer a case.
  public func value<Value: RawRepresentable>(_: Value.Type, module: String, field: String) -> Value?
  where Value.RawValue == String {
    guard let raw = string(module: module, field: field) else { return nil }
    return Value(rawValue: raw)
  }

  /// nil or an empty string forgets the field.
  public func set(_ value: String?, module: String, field: String) {
    guard let key = key(module, field) else { return }
    if let value, !value.isEmpty {
      defaults.set(value, forKey: key)
    } else {
      defaults.removeObject(forKey: key)
    }
  }

  public func set(_ value: Bool, module: String, field: String) {
    guard let key = key(module, field) else { return }
    defaults.set(value, forKey: key)
  }

  /// nil forgets the field.
  public func set<Value: RawRepresentable>(_ value: Value?, module: String, field: String)
  where Value.RawValue == String {
    set(value?.rawValue, module: module, field: field)
  }

  private func key(_ module: String, _ field: String) -> String? {
    account.map { "\($0).\(module).\(field)" }
  }
}

/// One remembered enum of a store, such as its tab: read when the store is
/// built, read again when another account signs in, written on each change.
public struct RememberedValue<Value: RawRepresentable> where Value.RawValue == String {
  private let viewState: ViewStateStore?
  private let module: String
  private let field: String

  /// A nil `viewState` remembers nothing.
  public init(_ viewState: ViewStateStore?, module: String, field: String) {
    self.viewState = viewState
    self.module = module
    self.field = field
  }

  public var stored: Value? { viewState?.value(Value.self, module: module, field: field) }

  public func save(_ value: Value) {
    viewState?.set(value, module: module, field: field)
  }

  /// Calls `apply` with the stored value now, and again after every account
  /// switch while `owner` lives. `apply` must hold `owner` weakly.
  public func bind(_ owner: AnyObject, apply: @escaping (Value?) -> Void) {
    apply(stored)
    viewState?.observe(owner) { [self] in apply(stored) }
  }
}
