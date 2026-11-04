import DailyAPI
import Foundation
import os

// `@unchecked`: `UserDefaults` is not marked `Sendable`, but Apple documents it
// as thread-safe, and the only stored reference here is immutable.

/// Keeps the chosen server in `UserDefaults`, as an absolute URL string under `key`.
/// No default value: the first launch asks for the server (docs/plan.md, "Autenticação e rede").
public struct UserDefaultsServerSettings: ServerSettings, @unchecked Sendable {
  /// `UserDefaults` key holding the server URL string.
  public static let key = "io.github.novaisvictor.dailyweb.serverURL"

  private let defaults: UserDefaults
  private let logger = Logger(subsystem: "io.github.novaisvictor.dailyweb", category: "DailyStorage")

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  public var serverURL: URL? {
    guard let text = defaults.string(forKey: Self.key) else { return nil }
    guard let url = URL(string: text), ServerOrigin(url) != nil else {
      // The protocol getter cannot throw; an unreadable value means "not configured"
      // and the login screen asks again.
      logger.error("Stored server URL is invalid: \(text, privacy: .public)")
      return nil
    }
    return url
  }

  public func setServerURL(_ url: URL?) {
    if let url {
      defaults.set(url.absoluteString, forKey: Self.key)
    } else {
      defaults.removeObject(forKey: Self.key)
    }
  }
}
