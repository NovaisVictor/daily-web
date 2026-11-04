import DailyAPI
import Foundation

/// The client features receive. It forwards every call and, when one answers
/// `.unauthorized`, tells the session so the app goes back to the login screen
/// (`middleware.ts:37-40`: no refresh, no retry).
public nonisolated struct SessionAwareClient: APIClient {
  private let base: any APIClient
  private let onUnauthorized: @MainActor @Sendable () -> Void

  public init(_ base: any APIClient, onUnauthorized: @escaping @MainActor @Sendable () -> Void) {
    self.base = base
    self.onUnauthorized = onUnauthorized
  }

  public func send<Response>(_ endpoint: Endpoint<Response>) async throws(APIError) -> Response {
    do {
      return try await base.send(endpoint)
    } catch .unauthorized {
      await onUnauthorized()
      throw .unauthorized
    }
  }

  /// Wrong credentials answer `.server` here, never `.unauthorized`, so there is
  /// no session to invalidate.
  public func signIn(server: URL, username: String, password: String) async throws(APIError) {
    try await base.signIn(server: server, username: username, password: password)
  }

  public func signOut() async {
    await base.signOut()
  }
}
