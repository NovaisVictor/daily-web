import DailyAPI
import Foundation
import Synchronization

/// Records every call (method, path, body) and answers through `handler`.
nonisolated final class FakeAPIClient: APIClient {
  struct Call: Equatable, Sendable, CustomStringConvertible {
    let method: String
    let path: String
    /// JSON with sorted keys, or nil without a body.
    let body: String?

    var description: String { "\(method) \(path) \(body ?? "-")" }
  }

  typealias Handler = @Sendable (Call) async throws(APIError) -> Data

  private struct State {
    var calls: [Call] = []
    var handler: Handler
  }

  private let state: Mutex<State>

  init(handler: @escaping Handler = { _ in FakeAPIClient.ok }) {
    state = Mutex(State(handler: handler))
  }

  static let ok = Data(#"{"ok":true}"#.utf8)

  static func json<Value: Encodable>(_ value: Value) -> Data {
    do {
      return try JSONEncoder().encode(value)
    } catch {
      preconditionFailure("Test value failed to encode: \(error)")
    }
  }

  var calls: [Call] { state.withLock { $0.calls } }

  /// Every call except the dashboard reads, which every write is followed by.
  var writes: [Call] { calls.filter { $0.path != "/api/state" } }

  func respond(_ handler: @escaping Handler) {
    state.withLock { $0.handler = handler }
  }

  func send<Response>(_ endpoint: Endpoint<Response>) async throws(APIError) -> Response {
    let call = Call(method: endpoint.method.rawValue, path: endpoint.path, body: Self.encode(endpoint.body))
    let handler = state.withLock { state in
      state.calls.append(call)
      return state.handler
    }
    let data = try await handler(call)
    if let empty = EmptyResponse() as? Response { return empty }
    do {
      return try JSONDecoder().decode(Response.self, from: data)
    } catch {
      throw .decoding(detail: String(describing: error))
    }
  }

  func signIn(server: URL, username: String, password: String) async throws(APIError) {}

  func signOut() async {}

  static func encode(_ body: (any Encodable & Sendable)?) -> String? {
    guard let body else { return nil }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    do {
      return String(decoding: try encoder.encode(body), as: UTF8.self)
    } catch {
      preconditionFailure("Request body failed to encode: \(error)")
    }
  }
}

/// Holds a fake response until the test opens it.
nonisolated final class Gate: Sendable {
  private let stream: AsyncStream<Void>
  private let continuation: AsyncStream<Void>.Continuation

  init() {
    (stream, continuation) = AsyncStream.makeStream(of: Void.self)
  }

  func wait() async {
    for await _ in stream {}
  }

  func open() {
    continuation.finish()
  }
}
