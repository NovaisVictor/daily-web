import DailyAPI
import DailyModels
import Foundation
import Observation
import os

/// Who is using the app, and whether the login screen shows.
@Observable
public final class SessionStore {
  public enum Phase: Equatable {
    /// Checking the stored token at launch.
    case restoring
    /// The login screen; `message` explains why, e.g. an expired session.
    case signedOut(message: String?)
    case signedIn(CurrentUser)
  }

  /// `APIError.unauthorized.userMessage`, shown on the login screen after a 401.
  public static let expiredMessage = "Sua sessão expirou. Entre de novo."

  public private(set) var phase: Phase = .restoring
  /// Why `restore()` could not decide (offline, server error). The phase stays
  /// `.restoring` and the UI offers to try again: a network failure is not a
  /// reason to throw the session away.
  public private(set) var restoreError: APIError?

  public var user: CurrentUser? {
    if case .signedIn(let user) = phase { return user }
    return nil
  }

  /// Runs after every transition into `.signedIn` (restore or login).
  @ObservationIgnored public var onSignedIn: ((CurrentUser) -> Void)?
  /// Runs after every transition out of `.signedIn` (logout or 401).
  @ObservationIgnored public var onSignedOut: (() -> Void)?

  @ObservationIgnored private let client: any APIClient
  @ObservationIgnored private let tokenStore: any SessionTokenStore
  @ObservationIgnored private let settings: any ServerSettings

  /// - Parameter client: The raw client, not `SessionAwareClient`: the store
  ///   handles its own 401s.
  public init(client: any APIClient, tokenStore: any SessionTokenStore, settings: any ServerSettings) {
    self.client = client
    self.tokenStore = tokenStore
    self.settings = settings
  }

  /// The server the user last signed in to, to prefill the login screen.
  public var serverURL: URL? { settings.serverURL }

  /// Checks the stored token with `GET /api/me`.
  public func restore() async {
    phase = .restoring
    restoreError = nil
    guard let server = settings.serverURL else {
      phase = .signedOut(message: nil)
      return
    }
    let token: String?
    do {
      token = try tokenStore.token(for: server)
    } catch {
      Logger.core.error("Could not read the session token: \(String(describing: error), privacy: .public)")
      phase = .signedOut(message: nil)
      return
    }
    guard token != nil else {
      phase = .signedOut(message: nil)
      return
    }
    do {
      let user = try await client.send(CoreEndpoints.me)
      enterSignedIn(user)
    } catch .unauthorized {
      phase = .signedOut(message: Self.expiredMessage)
    } catch {
      Logger.core.error("Session restore failed: \(String(describing: error), privacy: .public)")
      restoreError = error
    }
  }

  /// `POST /api/login`, then `GET /api/me`. Returns the message to show, or nil on success.
  public func signIn(server: URL, username: String, password: String) async -> String? {
    do {
      try await client.signIn(server: server, username: username, password: password)
      let user = try await client.send(CoreEndpoints.me)
      enterSignedIn(user)
      return nil
    } catch {
      Logger.core.error("Sign in failed: \(String(describing: error), privacy: .public)")
      return error.userMessage
    }
  }

  /// `POST /api/logout` and back to the login screen.
  public func signOut() async {
    await client.signOut()
    leave(message: nil)
  }

  /// A call answered 401: the client already forgot the token.
  public func invalidate() {
    guard case .signedIn = phase else { return }
    Logger.core.notice("Session expired; returning to the login screen")
    leave(message: Self.expiredMessage)
  }

  /// After `PATCH /api/me` or an avatar change.
  public func updateUser(_ user: CurrentUser) {
    guard case .signedIn = phase else { return }
    phase = .signedIn(user)
  }

  private func enterSignedIn(_ user: CurrentUser) {
    restoreError = nil
    phase = .signedIn(user)
    onSignedIn?(user)
  }

  private func leave(message: String?) {
    let wasSignedIn = user != nil
    phase = .signedOut(message: message)
    if wasSignedIn { onSignedOut?() }
  }
}

extension SessionStore {
  /// Previews start signed in without a network round trip.
  func assumeSignedIn(_ user: CurrentUser) {
    phase = .signedIn(user)
  }
}
