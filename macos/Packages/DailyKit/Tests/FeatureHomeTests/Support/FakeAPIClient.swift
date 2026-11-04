import DailyAPI
import Foundation
import Synchronization

/// Records every call (method, path, body) and answers through `handler`.
nonisolated final class FakeAPIClient: APIClient {
  struct Call: Equatable, Sendable {
    let method: String
    let path: String
    /// JSON with sorted keys, or nil without a body.
    let body: String?
  }

  typealias Handler = @Sendable (Call) async throws(APIError) -> Data

  private struct State {
    var calls: [Call] = []
    var handler: Handler
    var signInError: APIError?
    var signOutCount = 0
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
  var signOutCount: Int { state.withLock { $0.signOutCount } }

  func respond(_ handler: @escaping Handler) {
    state.withLock { $0.handler = handler }
  }

  func failSignIn(with error: APIError?) {
    state.withLock { $0.signInError = error }
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

  func signIn(server: URL, username: String, password: String) async throws(APIError) {
    let error = state.withLock { state in
      state.calls.append(Call(method: "POST", path: "/api/login", body: nil))
      return state.signInError
    }
    if let error { throw error }
  }

  func signOut() async {
    state.withLock { $0.signOutCount += 1 }
  }

  private static func encode(_ body: (any Encodable & Sendable)?) -> String? {
    guard let body else { return nil }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    do {
      return String(decoding: try encoder.encode(body), as: UTF8.self)
    } catch {
      preconditionFailure("Request body failed to encode: \(error)")
    }
  }
}
