import DailyAPI
import DailyCore
import DailyModels
import Foundation
import Synchronization

/// Records every call (method, path, query, body) and answers through `handler`.
nonisolated final class FakeAPIClient: APIClient {
  struct Call: Equatable, Sendable {
    let method: String
    let path: String
    /// `name=value` pairs joined by `&`, empty without a query.
    let query: String
    /// JSON with sorted keys, or nil without a body.
    let body: String?

    init(_ method: String, _ path: String, query: String = "", body: String? = nil) {
      self.method = method
      self.path = path
      self.query = query
      self.body = body
    }
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

  /// Every call but the dashboard reloads, which most tests do not care about.
  var actionCalls: [Call] { calls.filter { $0.path != "/api/state" } }

  func respond(_ handler: @escaping Handler) {
    state.withLock { $0.handler = handler }
  }

  func send<Response>(_ endpoint: Endpoint<Response>) async throws(APIError) -> Response {
    let query = endpoint.query.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
    let call = Call(endpoint.method.rawValue, endpoint.path, query: query, body: Self.encode(endpoint.body))
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

func quietToasts() -> ToastCenter {
  ToastCenter(dismissDelay: .seconds(3600), sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
}
