import Foundation

// FROZEN INTERFACE (T006). T102 provides the URLSession implementation; tests
// and previews use their own conforming fakes.

/// Sends typed calls to the configured daily-web server.
public protocol APIClient: Sendable {
  /// Performs the call with the stored session. A 401 clears the stored token
  /// and throws `.unauthorized`.
  func send<Response>(_ endpoint: Endpoint<Response>) async throws(APIError) -> Response

  /// `POST /api/login`; on success keeps the `daily_web_session` cookie value
  /// from `Set-Cookie` through `SessionTokenStore` for the given server.
  func signIn(server: URL, username: String, password: String) async throws(APIError)

  /// `POST /api/logout`, then forgets the stored token even if the call fails.
  func signOut() async
}

/// Where the session token lives between launches. T102 implements it on the
/// Keychain in `DailyStorage`.
public protocol SessionTokenStore: Sendable {
  func token(for server: URL) throws -> String?
  func save(_ token: String, for server: URL) throws
  func deleteToken(for server: URL) throws
}

/// The server the app talks to, chosen on the login screen.
public protocol ServerSettings: Sendable {
  var serverURL: URL? { get }
  func setServerURL(_ url: URL?)
}
