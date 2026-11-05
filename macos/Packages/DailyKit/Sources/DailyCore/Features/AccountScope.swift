import DailyAPI
import Foundation

/// The `UserDefaults` keys of values kept per account (server origin and
/// username), and the account signed in last, so what a window builds at
/// launch reads its values before the session is checked.
///
/// Shared by `PreferencesStore` and `ViewStateStore`. The key formats are on
/// disk: changing them would forget what every account remembered.
struct AccountScope {
  /// Prefix of every per-account key.
  let prefix: String
  /// Names the key of the account signed in last.
  let lastAccountKey: String
  let defaults: UserDefaults

  /// `<prefix>.<origin>|<username>`; nil for a server without an http(s) origin.
  static func key(prefix: String, server: URL, username: String) -> String? {
    guard let origin = ServerOrigin(server) else { return nil }
    return "\(prefix).\(origin.description)|\(username)"
  }

  /// The key of the account signed in last; nil when signed out.
  var lastAccount: String? { defaults.string(forKey: lastAccountKey) }

  /// Makes the account the last one and returns its key. A server without an
  /// http(s) origin has no key: the last account is forgotten and nil returned.
  func activate(server: URL, username: String) -> String? {
    guard let key = Self.key(prefix: prefix, server: server, username: username) else {
      deactivate()
      return nil
    }
    defaults.set(key, forKey: lastAccountKey)
    return key
  }

  /// Signed out: no account is the last one. Its values stay on disk.
  func deactivate() {
    defaults.removeObject(forKey: lastAccountKey)
  }
}
