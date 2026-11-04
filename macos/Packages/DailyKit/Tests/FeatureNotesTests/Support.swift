import DailyAPI
import DailyModels
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
  /// Calls other than the Drive status poll.
  var writes: [Call] { calls.filter { $0.method != "GET" } }

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

/// Time that only moves when the test says so. Sleepers resume in deadline order.
@MainActor
final class VirtualClock {
  private(set) var elapsed: Duration = .zero
  private var sleepers: [(id: Int, deadline: Duration, continuation: CheckedContinuation<Void, any Error>)] = []
  private var nextID = 0

  func sleep(_ duration: Duration) async throws {
    nextID += 1
    let id = nextID
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
        if Task.isCancelled {
          continuation.resume(throwing: CancellationError())
        } else {
          sleepers.append((id, elapsed + duration, continuation))
        }
      }
    } onCancel: {
      Task { @MainActor in self.cancel(id) }
    }
  }

  func advance(by duration: Duration) async {
    let target = elapsed + duration
    await settle()
    while let next = sleepers.filter({ $0.deadline <= target }).min(by: { $0.deadline < $1.deadline }) {
      elapsed = next.deadline
      sleepers.removeAll { $0.id == next.id }
      next.continuation.resume()
      await settle()
    }
    elapsed = target
    await settle()
  }

  private func cancel(_ id: Int) {
    guard let index = sleepers.firstIndex(where: { $0.id == id }) else { return }
    sleepers.remove(at: index).continuation.resume(throwing: CancellationError())
  }
}

/// Lets every ready main-actor task run.
@MainActor
func settle() async {
  for _ in 0..<200 { await Task.yield() }
}

nonisolated func note(_ id: String, _ title: String = "", _ body: String = "", folder: String? = nil) -> Note {
  Note(id: id, title: title, body: body, position: 0, updatedAt: "2026-09-01T00:00:00.000Z", folderId: folder)
}

nonisolated func folder(_ id: String, parent: String? = nil, position: Int = 0, name: String? = nil) -> NoteFolder {
  NoteFolder(id: id, name: name ?? id, parentId: parent, position: position, updatedAt: "2026-09-01T00:00:00.000Z")
}

nonisolated let disconnected = NotesSyncStatus(
  connected: false, account: "", pending: 0, lastError: nil, lastSyncedAt: nil)

nonisolated func serverError(_ message: String, status: Int = 400) -> APIError {
  .server(status: status, message: message, code: nil, retry: nil)
}
