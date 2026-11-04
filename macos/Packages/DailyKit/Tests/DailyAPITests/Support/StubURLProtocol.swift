import Foundation
import Synchronization

@testable import DailyAPI

/// What the stub server answers.
enum StubReply: Sendable {
  case http(status: Int, headers: [String: String] = [:], body: Data = Data())
  case failure(URLError.Code)

  static func json(_ status: Int, _ text: String, headers: [String: String] = [:]) -> StubReply {
    .http(status: status, headers: headers.merging(["Content-Type": "application/json"]) { $1 }, body: Data(text.utf8))
  }
}

/// A request as the stub saw it, with the body read back from its stream.
struct RecordedRequest: Sendable {
  let method: String
  let url: URL
  let headers: [String: String]
  let body: Data?

  func header(_ name: String) -> String? {
    headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
  }
}

/// One fake server, reachable at a host unique to the test so parallel tests never share replies.
final class StubServer: Sendable {
  let origin: URL
  private let state: Mutex<(replies: [StubReply], requests: [RecordedRequest])>

  init(port: Int? = nil, replies: [StubReply]) {
    let host = "stub-\(UUID().uuidString.lowercased()).test"
    var components = URLComponents()
    components.scheme = "http"
    components.host = host
    components.port = port
    guard let url = components.url else { preconditionFailure("Invalid stub origin") }
    origin = url
    state = Mutex((replies: replies, requests: []))
    StubURLProtocol.register(self, host: host)
  }

  var requests: [RecordedRequest] { state.withLock { $0.requests } }

  func handle(_ request: RecordedRequest) -> StubReply {
    state.withLock { state in
      state.requests.append(request)
      guard !state.replies.isEmpty else { return .failure(.resourceUnavailable) }
      return state.replies.removeFirst()
    }
  }

  /// A session configured like production, with the stub in front of the network.
  func makeSession() -> URLSession {
    let configuration = HTTPAPIClient.makeSessionConfiguration()
    configuration.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: configuration)
  }
}

final class StubURLProtocol: URLProtocol {
  private static let servers = Mutex<[String: StubServer]>([:])

  static func register(_ server: StubServer, host: String) {
    servers.withLock { $0[host] = server }
  }

  override class func canInit(with request: URLRequest) -> Bool { true }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let url = request.url, let host = url.host(), let server = Self.servers.withLock({ $0[host] }) else {
      client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
      return
    }
    let recorded = RecordedRequest(
      method: request.httpMethod ?? "GET",
      url: url,
      headers: request.allHTTPHeaderFields ?? [:],
      body: request.httpBody ?? request.httpBodyStream.map(Self.read)
    )
    switch server.handle(recorded) {
    case .failure(let code):
      client?.urlProtocol(self, didFailWithError: URLError(code))
    case .http(let status, let headers, let body):
      guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)
      else {
        client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
        return
      }
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: body)
      client?.urlProtocolDidFinishLoading(self)
    }
  }

  override func stopLoading() {}

  private static func read(_ stream: InputStream) -> Data {
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
      let count = stream.read(&buffer, maxLength: buffer.count)
      guard count > 0 else { break }
      data.append(buffer, count: count)
    }
    return data
  }
}

/// In-memory token store that can be told to fail.
final class MemoryTokenStore: SessionTokenStore {
  struct Failure: Error {}

  private let tokens: Mutex<[URL: String]>
  private let failing: Bool

  init(_ tokens: [URL: String] = [:], failing: Bool = false) {
    self.tokens = Mutex(tokens)
    self.failing = failing
  }

  func token(for server: URL) throws -> String? {
    if failing { throw Failure() }
    return tokens.withLock { $0[server] }
  }

  func save(_ token: String, for server: URL) throws {
    if failing { throw Failure() }
    tokens.withLock { $0[server] = token }
  }

  func deleteToken(for server: URL) throws {
    if failing { throw Failure() }
    tokens.withLock { $0[server] = nil }
  }

  var all: [URL: String] { tokens.withLock { $0 } }
}

final class MemoryServerSettings: ServerSettings {
  private let url: Mutex<URL?>

  init(_ url: URL? = nil) {
    self.url = Mutex(url)
  }

  var serverURL: URL? { url.withLock { $0 } }

  func setServerURL(_ url: URL?) {
    self.url.withLock { $0 = url }
  }
}
