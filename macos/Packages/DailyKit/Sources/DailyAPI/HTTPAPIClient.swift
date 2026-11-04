import Foundation
import os

/// The `URLSession` implementation of `APIClient`.
///
/// It holds no mutable state of its own: the token lives in `SessionTokenStore`
/// and the server in `ServerSettings`, so every stored property is an immutable
/// `Sendable` value and the class is `Sendable` without locks.
public final class HTTPAPIClient: APIClient {
  /// Name of the session cookie (`lib/auth/session.ts:4`).
  public static let sessionCookieName = "daily_web_session"

  private let session: URLSession
  private let tokenStore: any SessionTokenStore
  private let settings: any ServerSettings
  private let logger: Logger
  private let now: @Sendable () -> Date
  private let makeIdempotencyKey: @Sendable () -> String

  /// - Parameters:
  ///   - session: Must come from `makeSessionConfiguration()` (tests add their
  ///     protocol classes to it).
  ///   - now: Clock for `X-Request-Timestamp`.
  ///   - makeIdempotencyKey: Source of `Idempotency-Key` values.
  public init(
    tokenStore: any SessionTokenStore,
    settings: any ServerSettings,
    session: URLSession = URLSession(configuration: HTTPAPIClient.makeSessionConfiguration()),
    logger: Logger = Logger(subsystem: "io.github.novaisvictor.dailyweb", category: "DailyAPI"),
    now: @escaping @Sendable () -> Date = { Date() },
    makeIdempotencyKey: @escaping @Sendable () -> String = { UUID().uuidString }
  ) {
    self.session = session
    self.tokenStore = tokenStore
    self.settings = settings
    self.logger = logger
    self.now = now
    self.makeIdempotencyKey = makeIdempotencyKey
  }

  /// The session cookie is `secure` (`app/api/login/route.ts:44`), so a cookie
  /// store would not send it to `http://localhost`. The client builds the
  /// `Cookie` header itself and keeps URLSession's cookie handling off.
  public static func makeSessionConfiguration() -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.httpCookieAcceptPolicy = .never
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    // Same 30 s budget the web gives its slowest calls (docs/plan.md, "Autenticação e rede").
    configuration.timeoutIntervalForRequest = 30
    return configuration
  }

  // MARK: - APIClient

  public func send<Response>(_ endpoint: Endpoint<Response>) async throws(APIError) -> Response {
    guard let server = settings.serverURL, let origin = ServerOrigin(server) else {
      throw .notConfigured
    }
    let token = try storedToken(for: origin)
    let request = try makeRequest(endpoint, origin: origin, token: token)
    let (data, response) = try await perform(request, label: endpoint.path)

    if response.statusCode == 401, !(endpoint.checksCredentials && !Self.isMiddlewareRejection(data)) {
      // `middleware.ts:37-40`: the token is invalid or expired; there is no refresh.
      logger.notice("\(endpoint.path, privacy: .public) answered 401; forgetting the session")
      forgetToken(for: origin)
      throw .unauthorized
    }
    try ensureSuccess(response, data: data, label: endpoint.path)
    return try decode(Response.self, from: data, response: response, label: endpoint.path)
  }

  public func signIn(server: URL, username: String, password: String) async throws(APIError) {
    guard let origin = ServerOrigin(server) else { throw .notConfigured }
    let endpoint = Endpoint<EmptyResponse>(
      .post, "/api/login", body: Credentials(username: username, password: password))
    // No stored token is sent: a stale one must not decide who signs in.
    let request = try makeRequest(endpoint, origin: origin, token: nil)
    let (data, response) = try await perform(request, label: endpoint.path)
    // A 401 here means wrong credentials ("usuário ou senha inválidos",
    // `app/api/login/route.ts:35`), not an expired session, so the server's
    // message is shown instead of `.unauthorized`.
    try ensureSuccess(response, data: data, label: endpoint.path)

    guard let token = sessionCookie(in: response, for: request.url ?? origin.url) else {
      logger.error("/api/login answered \(response.statusCode) without a session cookie")
      throw .invalidResponse
    }
    do {
      try tokenStore.save(token, for: origin.url)
    } catch {
      logger.error("Could not store the session token: \(String(describing: error), privacy: .public)")
      throw .storage(detail: String(describing: error))
    }
    settings.setServerURL(origin.url)
    logger.info("Signed in to \(origin.description, privacy: .public)")
  }

  public func signOut() async {
    guard let server = settings.serverURL, let origin = ServerOrigin(server) else {
      logger.notice("Sign out without a configured server; nothing to forget")
      return
    }
    // The logout call only clears the browser cookie (`app/api/logout/route.ts`);
    // the server keeps no session, so a failure here is logged and the local
    // token is forgotten anyway.
    do {
      let token = try storedToken(for: origin)
      let request = try makeRequest(Endpoint<EmptyResponse>(.post, "/api/logout"), origin: origin, token: token)
      let (data, response) = try await perform(request, label: "/api/logout")
      try ensureSuccess(response, data: data, label: "/api/logout")
    } catch {
      logger.error("Logout call failed: \(String(describing: error), privacy: .public)")
    }
    forgetToken(for: origin)
  }

  // MARK: - Request

  private struct Credentials: Encodable, Sendable {
    let username: String
    let password: String
  }

  private func makeRequest<Response>(
    _ endpoint: Endpoint<Response>, origin: ServerOrigin, token: String?
  ) throws(APIError) -> URLRequest {
    guard var components = URLComponents(string: origin.description + endpoint.path) else {
      logger.fault("Invalid endpoint path \(endpoint.path, privacy: .public)")
      throw .invalidResponse
    }
    if !endpoint.query.isEmpty {
      components.queryItems = endpoint.query
    }
    guard let url = components.url else {
      logger.fault("Could not build a URL for \(endpoint.path, privacy: .public)")
      throw .invalidResponse
    }

    var request = URLRequest(url: url)
    request.httpMethod = endpoint.method.rawValue
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let token {
      request.setValue("\(Self.sessionCookieName)=\(token)", forHTTPHeaderField: "Cookie")
    }
    if endpoint.method.isWrite {
      // `verifyOrigin` (`lib/agents/http.ts:12`) requires it on browser writes.
      request.setValue(origin.description, forHTTPHeaderField: "Origin")
    }
    if let body = endpoint.body {
      do {
        request.httpBody = try JSONEncoder().encode(body)
      } catch {
        logger.fault("Could not encode the body of \(endpoint.path, privacy: .public): \(error, privacy: .public)")
        throw .decoding(detail: "Request body: \(error)")
      }
      // `body()` refuses anything else (`lib/agents/http.ts:16`).
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    if endpoint.idempotent {
      // Read by `mutation()` (`lib/agents/http.ts:15`) and the pulls writes
      // (`app/api/pulls/shared.ts:15`); validated in `lib/access/receipts.ts:14-17`.
      // The server's own fallback is `new Date().toISOString()`, hence `JSISODate`.
      request.setValue(makeIdempotencyKey(), forHTTPHeaderField: "Idempotency-Key")
      request.setValue(JSISODate.string(from: now()), forHTTPHeaderField: "X-Request-Timestamp")
    }
    return request
  }

  // MARK: - Response

  private func perform(_ request: URLRequest, label: String) async throws(APIError) -> (Data, HTTPURLResponse) {
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch let error as URLError {
      logger.error("\(label, privacy: .public) failed: URLError \(error.code.rawValue)")
      throw Self.map(error)
    } catch is CancellationError {
      throw .cancelled
    } catch {
      logger.error("\(label, privacy: .public) failed: \(String(describing: error), privacy: .public)")
      throw .invalidResponse
    }
    guard let http = response as? HTTPURLResponse else {
      logger.error("\(label, privacy: .public) returned a non-HTTP response")
      throw .invalidResponse
    }
    return (data, http)
  }

  static func map(_ error: URLError) -> APIError {
    switch error.code {
    case .notConnectedToInternet, .cannotConnectToHost, .networkConnectionLost, .cannotFindHost, .dnsLookupFailed:
      .offline
    case .timedOut:
      .timedOut
    case .cancelled:
      .cancelled
    case .appTransportSecurityRequiresSecureConnection:
      // ATS refuses plain `http` except for local addresses.
      .insecureConnection
    case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
      .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
      .untrustedCertificate
    default:
      .invalidResponse
    }
  }

  private func ensureSuccess(_ response: HTTPURLResponse, data: Data, label: String) throws(APIError) {
    guard !(200..<300).contains(response.statusCode) else { return }
    let status = response.statusCode
    let error = Self.serverError(status: status, data: data)
    logger.error("\(label, privacy: .public) answered \(status)")
    throw error
  }

  static func serverError(status: Int, data: Data) -> APIError {
    let fallback = "Erro \(status) do servidor"
    let body: ServerErrorBody
    do {
      body = try JSONDecoder().decode(ServerErrorBody.self, from: data)
    } catch {
      // Proxies and crashes answer with HTML or nothing; the status still tells the story.
      return .server(status: status, message: fallback, code: nil, retry: nil)
    }
    let message = body.message.isEmpty ? fallback : body.message
    return .server(status: status, message: message, code: body.code, retry: body.retry.flatMap(RetryHint.init))
  }

  private func decode<Response: Decodable>(
    _ type: Response.Type, from data: Data, response: HTTPURLResponse, label: String
  ) throws(APIError) -> Response {
    if response.statusCode == 204 || data.isEmpty, let empty = EmptyResponse() as? Response {
      return empty
    }
    do {
      return try JSONDecoder().decode(Response.self, from: data)
    } catch {
      logger.error("\(label, privacy: .public) decoding failed: \(String(describing: error), privacy: .public)")
      throw .decoding(detail: String(describing: error))
    }
  }

  private func sessionCookie(in response: HTTPURLResponse, for url: URL) -> String? {
    var fields: [String: String] = [:]
    for (key, value) in response.allHeaderFields {
      if let key = key as? String, let value = value as? String {
        fields[key] = value
      }
    }
    // `HTTPCookie` drops `Secure` cookies when parsing for an `http` URL, and the
    // server always marks this one `secure` (`app/api/login/route.ts:44`), also
    // on a local `http://localhost`. Only the value is needed, so it is parsed
    // as if the response came over https.
    var parseURL = URLComponents(url: url, resolvingAgainstBaseURL: false)
    parseURL?.scheme = "https"
    let cookie = HTTPCookie.cookies(withResponseHeaderFields: fields, for: parseURL?.url ?? url)
      .first { $0.name == Self.sessionCookieName && !$0.value.isEmpty }
    return cookie?.value
  }

  /// The middleware's 401 body (`middleware.ts:38`), as opposed to a route
  /// rejecting a credential the person typed.
  static func isMiddlewareRejection(_ data: Data) -> Bool {
    do {
      return try JSONDecoder().decode(ServerErrorBody.self, from: data).message == "não autenticado"
    } catch {
      // An unreadable 401 body is not a route's credential message: end the
      // session, which is the safe reading.
      return true
    }
  }

  // MARK: - Token

  private func storedToken(for origin: ServerOrigin) throws(APIError) -> String? {
    do {
      return try tokenStore.token(for: origin.url)
    } catch {
      logger.error("Could not read the session token: \(String(describing: error), privacy: .public)")
      // Without a readable token there is no session; the login screen is the
      // only way forward.
      throw .unauthorized
    }
  }

  private func forgetToken(for origin: ServerOrigin) {
    do {
      try tokenStore.deleteToken(for: origin.url)
    } catch {
      logger.error("Could not delete the session token: \(String(describing: error), privacy: .public)")
    }
  }
}
