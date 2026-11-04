import DailyCore
import DailyModels
import Foundation

/// Time that only moves when the test says so. Sleepers resume in deadline order.
@MainActor
final class VirtualClock {
  static let origin = Date(timeIntervalSince1970: 1_793_000_000)

  private(set) var elapsed: Duration = .zero
  private var sleepers: [(id: Int, deadline: Duration, continuation: CheckedContinuation<Void, any Error>)] = []
  private var nextID = 0

  var date: Date { Self.origin.addingTimeInterval(Self.seconds(elapsed)) }
  var pendingSleepers: Int { sleepers.count }

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

  static func seconds(_ duration: Duration) -> TimeInterval {
    Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
  }
}

/// Lets every ready main-actor task run.
@MainActor
func settle() async {
  for _ in 0..<200 { await Task.yield() }
}

/// Records what would be posted.
final class FakeNotificationPoster: NotificationPosting {
  var authorized = true
  var granted = true
  private(set) var posted: [DesktopAlert] = []
  private(set) var requests = 0

  func requestAuthorization() async -> Bool {
    requests += 1
    authorized = granted
    return granted
  }

  func isAuthorized() async -> Bool { authorized }

  func post(_ alert: DesktopAlert) async { posted.append(alert) }

  func clear() { posted.removeAll() }
}

nonisolated enum Fixtures {
  struct Missing: Error {}

  /// The shared state fixture of `DailyModelsTests`, read from the source tree
  /// (this test target bundles no resources).
  static func dashboard() throws -> DashboardState {
    let url = URL(filePath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appending(path: "DailyModelsTests/Fixtures/dashboard-state-full.json")
    return try JSONDecoder().decode(DashboardState.self, from: Data(contentsOf: url))
  }

  static func state(updatedAt: String = "2026-11-04T12:00:00.000Z", tasksView: TasksView = .list) -> DashboardState {
    DashboardState(updatedAt: updatedAt, modules: [.tasks], tasksView: tasksView)
  }

  static let user = CurrentUser(username: "ana", isAdmin: false, avatarUrl: nil, fullName: "Ana", email: nil)

  static func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appending(
      path: "DailyCoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
  }

  static func defaults() -> UserDefaults {
    let name = "DailyCoreTests-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: name) else {
      preconditionFailure("Could not create the defaults suite \(name)")
    }
    return defaults
  }
}

/// Toasts that stay until dismissed, so tests can read them.
func quietToasts() -> ToastCenter {
  ToastCenter(dismissDelay: .seconds(3600), sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
}
