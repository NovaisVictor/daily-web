import DailyAPI
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

  private let defaults: UserDefaults
  /// The key prefix of the signed-in account; nil reads nothing and writes nothing.
  private var account: String?

  public init(defaults: UserDefaults) {
    self.defaults = defaults
    account = defaults.string(forKey: Self.lastAccountKey)
  }

  /// Whether an account is active, so reads and writes reach the disk.
  public var isActive: Bool { account != nil }

  /// Switches to the values of the account that just signed in.
  public func activate(server: URL, username: String) {
    guard let origin = ServerOrigin(server) else {
      Logger.core.error("No remembered view state for a server without an http(s) origin")
      deactivate()
      return
    }
    let key = "\(Self.keyPrefix).\(origin.description)|\(username)"
    account = key
    defaults.set(key, forKey: Self.lastAccountKey)
  }

  /// Signed out: nothing is read or written until the next sign-in. The
  /// account's values stay on disk for it.
  public func deactivate() {
    account = nil
    defaults.removeObject(forKey: Self.lastAccountKey)
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

  private func key(_ module: String, _ field: String) -> String? {
    account.map { "\($0).\(module).\(field)" }
  }
}
