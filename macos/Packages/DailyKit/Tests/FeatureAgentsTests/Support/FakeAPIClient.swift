import DailyAPI
import DailyCore
import DailyModels
import Foundation
import Synchronization

/// Records every call (method, path, query, body, idempotency) and answers through `handler`.
nonisolated final class FakeAPIClient: APIClient {
  struct Call: Equatable, Sendable {
    let method: String
    let path: String
    /// `name=value` pairs joined by `&`, empty without a query.
    let query: String
    /// JSON with sorted keys, or nil without a body.
    let body: String?
    let idempotent: Bool
    var idempotencyKey: String? = nil
  }

  typealias Handler = @Sendable (Call) async throws(APIError) -> Data

  private let state: Mutex<(calls: [Call], handler: Handler)>

  init(handler: @escaping Handler = { _ in FakeAPIClient.ok }) {
    state = Mutex(([], handler))
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

  func respond(_ handler: @escaping Handler) {
    state.withLock { $0.handler = handler }
  }

  func send<Response>(_ endpoint: Endpoint<Response>) async throws(APIError) -> Response {
    let query = endpoint.query.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
    let call = Call(
      method: endpoint.method.rawValue, path: endpoint.path, query: query, body: Self.encode(endpoint.body),
      idempotent: endpoint.idempotent,
      idempotencyKey: endpoint.idempotencyKey)
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

/// Lets every ready main-actor task run.
@MainActor
func settle() async {
  for _ in 0..<200 { await Task.yield() }
}

/// A sleeper that never wakes within a test.
let neverWake: Sleeper = { _ in try await Task.sleep(for: .seconds(3600)) }
