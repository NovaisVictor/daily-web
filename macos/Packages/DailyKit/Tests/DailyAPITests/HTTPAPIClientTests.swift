import Foundation
import Testing

@testable import DailyAPI

private struct Item: Codable, Sendable, Equatable {
  var id: String
}

private struct Fixture {
  let server: StubServer
  let tokens: MemoryTokenStore
  let settings: MemoryServerSettings
  let client: HTTPAPIClient

  init(
    port: Int? = nil,
    token: String? = "signed.token",
    configured: Bool = true,
    failingStore: Bool = false,
    replies: [StubReply]
  ) {
    server = StubServer(port: port, replies: replies)
    var stored: [URL: String] = [:]
    if let token { stored[server.origin] = token }
    tokens = MemoryTokenStore(stored, failing: failingStore)
    settings = MemoryServerSettings(configured ? server.origin : nil)
    client = HTTPAPIClient(
      tokenStore: tokens,
      settings: settings,
      session: server.makeSession(),
      now: { Date(timeIntervalSince1970: 1_793_795_445.123) },
      makeIdempotencyKey: { "11111111-2222-3333-4444-555555555555" }
    )
  }

  var request: RecordedRequest? { server.requests.first }
}

private func expectError(_ expected: APIError, _ call: () async throws(APIError) -> Void) async {
  do {
    try await call()
    Issue.record("Expected \(expected), got success")
  } catch {
    #expect(error == expected)
  }
}

// MARK: - Headers

@Test func readSendsSessionCookieAndNoWriteHeaders() async throws {
  let fixture = Fixture(replies: [.json(200, #"{"id":"a"}"#)])
  let item = try await fixture.client.send(Endpoint<Item>(.get, "/api/items"))

  #expect(item == Item(id: "a"))
  let request = try #require(fixture.request)
  #expect(request.method == "GET")
  #expect(request.url.absoluteString == fixture.server.origin.absoluteString + "/api/items")
  #expect(request.header("Cookie") == "daily_web_session=signed.token")
  #expect(request.header("Origin") == nil)
  #expect(request.header("Content-Type") == nil)
  #expect(request.header("Idempotency-Key") == nil)
  #expect(request.header("X-Request-Timestamp") == nil)
  #expect(request.header("Authorization") == nil)
}

@Test func requestWithoutStoredTokenHasNoCookie() async throws {
  let fixture = Fixture(token: nil, replies: [.json(200, #"{"id":"a"}"#)])
  _ = try await fixture.client.send(Endpoint<Item>(.get, "/api/items"))

  let request = try #require(fixture.request)
  #expect(request.header("Cookie") == nil)
}

@Test func queryItemsAreAppended() async throws {
  let fixture = Fixture(replies: [.json(200, #"{"id":"a"}"#)])
  _ = try await fixture.client.send(
    Endpoint<Item>(.get, "/api/items", query: [URLQueryItem(name: "q", value: "a b")]))

  let request = try #require(fixture.request)
  #expect(request.url.query() == "q=a%20b")
}

@Test(arguments: [HTTPMethod.post, .put, .patch, .delete])
func writesSendOriginWithPort(method: HTTPMethod) async throws {
  let fixture = Fixture(port: 3000, replies: [.json(200, "{}")])
  _ = try await fixture.client.send(Endpoint<EmptyResponse>(method, "/api/items/1"))

  let request = try #require(fixture.request)
  #expect(request.method == method.rawValue)
  #expect(request.header("Origin") == fixture.server.origin.absoluteString)
  #expect(request.header("Origin")?.hasSuffix(":3000") == true)
  #expect(request.header("Content-Type") == nil)
  #expect(request.header("Authorization") == nil)
}

@Test func bodySetsJSONContentType() async throws {
  let fixture = Fixture(replies: [.json(200, #"{"id":"b"}"#)])
  _ = try await fixture.client.send(Endpoint<Item>(.post, "/api/items", body: Item(id: "b")))

  let request = try #require(fixture.request)
  #expect(request.header("Content-Type") == "application/json")
  let body = try #require(request.body)
  #expect(try JSONDecoder().decode(Item.self, from: body) == Item(id: "b"))
}

@Test func idempotentWritesSendKeyAndTimestamp() async throws {
  let fixture = Fixture(replies: [.json(200, "{}")])
  _ = try await fixture.client.send(Endpoint<EmptyResponse>(.post, "/api/pulls/x/rerun", idempotent: true))

  let request = try #require(fixture.request)
  #expect(request.header("Idempotency-Key") == "11111111-2222-3333-4444-555555555555")
  #expect(request.header("X-Request-Timestamp") == "2026-11-04T12:30:45.123Z")
  #expect(request.header("Authorization") == nil)
}

@Test func timestampMatchesJavaScriptToISOString() {
  // `new Date(1793795445000).toISOString()` === "2026-11-04T12:30:45.000Z"
  #expect(JSISODate.string(from: Date(timeIntervalSince1970: 1_793_795_445)) == "2026-11-04T12:30:45.000Z")
}

@Test func jsISODateRoundsMillisecondsInsteadOfTruncating() {
  // 1793795445.123 is stored as …445.12299990654; truncating would print .122.
  #expect(JSISODate.string(from: Date(timeIntervalSince1970: 1_793_795_445.123)) == "2026-11-04T12:30:45.123Z")
  #expect(JSISODate.string(from: Date(timeIntervalSince1970: 1_793_795_445.9996)) == "2026-11-04T12:30:46.000Z")
  #expect(JSISODate.string(from: Date(timeIntervalSince1970: -0.001)) == "1969-12-31T23:59:59.999Z")
}

@Test func unconfiguredServerFailsWithoutNetwork() async {
  let fixture = Fixture(configured: false, replies: [])
  await expectError(.notConfigured) { () async throws(APIError) in
    _ = try await fixture.client.send(Endpoint<Item>(.get, "/api/items"))
  }
  #expect(fixture.server.requests.isEmpty)
}

// MARK: - Sign in and out

@Test func signInStoresTokenAndServer() async throws {
  let fixture = Fixture(
    token: "stale", configured: false,
    replies: [
      .json(
        200, #"{"ok":true}"#,
        headers: ["Set-Cookie": "daily_web_session=new.token; Path=/; Max-Age=2592000; HttpOnly; Secure; SameSite=lax"]
      )
    ])
  let entered = fixture.server.origin.appending(path: "login")
  try await fixture.client.signIn(server: entered, username: "ana", password: "secret")

  #expect(fixture.tokens.all[fixture.server.origin] == "new.token")
  #expect(fixture.settings.serverURL == fixture.server.origin)
  let request = try #require(fixture.request)
  #expect(request.method == "POST")
  #expect(request.url.path() == "/api/login")
  #expect(request.header("Cookie") == nil)
  #expect(request.header("Origin") == fixture.server.origin.absoluteString)
  #expect(request.header("Content-Type") == "application/json")
  let body = try JSONSerialization.jsonObject(with: try #require(request.body)) as? [String: String]
  #expect(body == ["username": "ana", "password": "secret"])
}

@Test func signInWithoutSessionCookieFails() async {
  let fixture = Fixture(token: nil, configured: false, replies: [.json(200, #"{"ok":true}"#)])
  await expectError(.invalidResponse) { () async throws(APIError) in
    try await fixture.client.signIn(server: fixture.server.origin, username: "ana", password: "secret")
  }
  #expect(fixture.tokens.all.isEmpty)
  #expect(fixture.settings.serverURL == nil)
}

@Test func signInWithWrongPasswordShowsServerMessage() async {
  let fixture = Fixture(
    token: nil, configured: false, replies: [.json(401, #"{"error":"usuário ou senha inválidos"}"#)])
  await expectError(.server(status: 401, message: "usuário ou senha inválidos", code: nil, retry: nil)) {
    () async throws(APIError) in
    try await fixture.client.signIn(server: fixture.server.origin, username: "ana", password: "wrong")
  }
  #expect(fixture.settings.serverURL == nil)
}

@Test func signOutCallsLogoutAndForgetsToken() async throws {
  let fixture = Fixture(replies: [.json(200, #"{"ok":true}"#)])
  await fixture.client.signOut()

  #expect(fixture.tokens.all.isEmpty)
  let request = try #require(fixture.request)
  #expect(request.url.path() == "/api/logout")
  #expect(request.header("Cookie") == "daily_web_session=signed.token")
  #expect(request.header("Origin") == fixture.server.origin.absoluteString)
}

@Test(arguments: [StubReply.failure(.notConnectedToInternet), .json(500, #"{"error":"falhou"}"#)])
func signOutForgetsTokenWhenLogoutFails(reply: StubReply) async {
  let fixture = Fixture(replies: [reply])
  await fixture.client.signOut()
  #expect(fixture.tokens.all.isEmpty)
}

// MARK: - Errors

@Test func unauthorizedDeletesToken() async {
  let fixture = Fixture(replies: [.json(401, #"{"error":"não autenticado"}"#)])
  await expectError(.unauthorized) { () async throws(APIError) in
    _ = try await fixture.client.send(Endpoint<Item>(.get, "/api/state"))
  }
  #expect(fixture.tokens.all.isEmpty)
}

@Test func unreadableTokenStoreIsUnauthorized() async {
  let fixture = Fixture(failingStore: true, replies: [])
  await expectError(.unauthorized) { () async throws(APIError) in
    _ = try await fixture.client.send(Endpoint<Item>(.get, "/api/state"))
  }
  #expect(fixture.server.requests.isEmpty)
}

@Test(arguments: [
  (#"{"error":"apenas admin"}"#, APIError.server(status: 403, message: "apenas admin", code: nil, retry: nil)),
  (
    #"{"error":{"code":"invalid_origin","message":"Same-origin request required","retry":"never"}}"#,
    .server(status: 403, message: "Same-origin request required", code: "invalid_origin", retry: .never)
  ),
  (
    #"{"error":"O estado do PR mudou","code":"uncertain_outcome","retry":"reconcile"}"#,
    .server(status: 403, message: "O estado do PR mudou", code: "uncertain_outcome", retry: .reconcile)
  ),
  ("<html>Bad gateway</html>", .server(status: 403, message: "Erro 403 do servidor", code: nil, retry: nil)),
  ("", .server(status: 403, message: "Erro 403 do servidor", code: nil, retry: nil)),
])
func serverErrorShapes(body: String, expected: APIError) async {
  let fixture = Fixture(replies: [.json(403, body)])
  await expectError(expected) { () async throws(APIError) in
    _ = try await fixture.client.send(Endpoint<Item>(.get, "/api/users"))
  }
  #expect(fixture.tokens.all.isEmpty == false)
}

@Test(arguments: [
  (URLError.Code.notConnectedToInternet, APIError.offline),
  (.cannotConnectToHost, .offline),
  (.networkConnectionLost, .offline),
  (.cannotFindHost, .offline),
  (.timedOut, .timedOut),
  (.cancelled, .cancelled),
  (.appTransportSecurityRequiresSecureConnection, .insecureConnection),
  (.secureConnectionFailed, .untrustedCertificate),
  (.serverCertificateUntrusted, .untrustedCertificate),
  (.serverCertificateHasBadDate, .untrustedCertificate),
  (.serverCertificateHasUnknownRoot, .untrustedCertificate),
  (.serverCertificateNotYetValid, .untrustedCertificate),
])
func urlErrorsMap(code: URLError.Code, expected: APIError) async {
  let fixture = Fixture(replies: [.failure(code)])
  await expectError(expected) { () async throws(APIError) in
    _ = try await fixture.client.send(Endpoint<Item>(.get, "/api/state"))
  }
}

@Test func emptyResponsesDecodeAsEmpty() async throws {
  let fixture = Fixture(replies: [.http(status: 204), .http(status: 200)])
  let noContent = try await fixture.client.send(Endpoint<EmptyResponse>(.delete, "/api/items/1"))
  let emptyOK = try await fixture.client.send(Endpoint<EmptyResponse>(.post, "/api/items/1"))
  #expect(noContent == EmptyResponse())
  #expect(emptyOK == EmptyResponse())
}

@Test func mismatchedBodyIsDecodingError() async {
  let fixture = Fixture(replies: [.json(200, #"{"name":"a"}"#)])
  do {
    _ = try await fixture.client.send(Endpoint<Item>(.get, "/api/items"))
    Issue.record("Expected a decoding error")
  } catch {
    guard case .decoding = error else {
      Issue.record("Expected .decoding, got \(error)")
      return
    }
  }
}

@Test func transportSecurityErrorsHaveTheirOwnMessages() {
  #expect(APIError.insecureConnection.userMessage == "Este servidor precisa usar HTTPS (ou ser um endereço local).")
  #expect(APIError.untrustedCertificate.userMessage == "O certificado do servidor não é confiável.")
}

// MARK: - Endpoints and origin

@Test(arguments: [
  ("abc-123_x.y~z", "abc-123_x.y~z"),
  ("a/b+c=d?e#f", "a%2Fb%2Bc%3Dd%3Fe%23f"),
  ("a b%c", "a%20b%25c"),
  ("!$&'()*,;:@", "!$&'()*,;:@"),
  ("ação", "a%C3%A7%C3%A3o"),
  ("🙂", "%F0%9F%99%82"),
  ("", ""),
])
func segmentPercentEncodesUTF8Bytes(input: String, expected: String) {
  #expect(Endpoint<EmptyResponse>.segment(input) == expected)
}

@Test func segmentMatchesFoundationForEveryASCIIByte() throws {
  var allowed = CharacterSet.urlPathAllowed
  allowed.remove(charactersIn: "/+=?#")
  for byte in UInt8(0)...UInt8(127) {
    let value = String(Character(Unicode.Scalar(byte)))
    let foundation = try #require(value.addingPercentEncoding(withAllowedCharacters: allowed))
    #expect(Endpoint<EmptyResponse>.segment(value) == foundation, "byte \(byte)")
  }
}

@Test func coreEndpoints() {
  #expect(CoreEndpoints.me.method == .get)
  #expect(CoreEndpoints.me.path == "/api/me")
  #expect(CoreEndpoints.state.method == .get)
  #expect(CoreEndpoints.state.path == "/api/state")
  #expect(CoreEndpoints.refresh.method == .post)
  #expect(CoreEndpoints.refresh.path == "/api/refresh")
}

@Test(arguments: [
  ("https://Daily.Example.com/login?x=1", "https://daily.example.com"),
  ("https://daily.example.com:443/", "https://daily.example.com"),
  ("http://localhost:3000/", "http://localhost:3000"),
  ("http://localhost:80", "http://localhost"),
])
func originNormalizes(input: String, expected: String) throws {
  let url = try #require(URL(string: input))
  #expect(ServerOrigin(url)?.description == expected)
}

@Test(arguments: ["ftp://example.com", "file:///tmp/x", "example.com"])
func originRejectsNonHTTP(input: String) throws {
  let url = try #require(URL(string: input))
  #expect(ServerOrigin(url) == nil)
}
