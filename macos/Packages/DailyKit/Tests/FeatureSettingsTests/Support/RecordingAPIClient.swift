import DailyAPI
import DailyCore
import Foundation
import Synchronization

/// Records every call (method, path, query, body) and answers through `handler`.
nonisolated final class RecordingAPIClient: APIClient {
  struct Call: Equatable, Sendable {
    let method: String
    let path: String
    let query: [URLQueryItem]
    /// JSON with sorted keys, or nil without a body.
    let body: String?
  }

  typealias Handler = @Sendable (Call) async throws(APIError) -> Data

  private let state: Mutex<(calls: [Call], handler: Handler)>

  init(handler: @escaping Handler = { _ in RecordingAPIClient.ok }) {
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
    let call = Call(
      method: endpoint.method.rawValue, path: endpoint.path, query: endpoint.query, body: Self.encode(endpoint.body))
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

  private static func encode(_ body: (any Encodable & Sendable)?) -> String? {
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

/// Toasts that never leave on their own, so tests can read them.
@MainActor
func quietToasts() -> ToastCenter {
  ToastCenter(sleep: { _ in throw CancellationError() })
}

/// A defaults suite of its own per test.
func scratchDefaults() -> UserDefaults {
  let name = "io.github.novaisvictor.dailyweb.tests.\(UUID().uuidString)"
  guard let defaults = UserDefaults(suiteName: name) else {
    preconditionFailure("Could not create the defaults suite \(name)")
  }
  return defaults
}
