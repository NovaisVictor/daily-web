import Foundation

/// Work that must finish before the app quits, such as a note's pending
/// autosave. The app delegate answers `applicationShouldTerminate` with
/// `.terminateLater` and waits for `flushAll()`.
public final class ShutdownTasks {
  private var tasks: [String: () async -> Void] = [:]

  public init() {}

  /// Registers (or replaces) the flush for `id`; screens unregister when they go away.
  public func register(_ id: String, flush: @escaping () async -> Void) {
    tasks[id] = flush
  }

  public func unregister(_ id: String) {
    tasks[id] = nil
  }

  /// Runs every registered flush, one after the other, and returns when all are done.
  public func flushAll() async {
    for flush in Array(tasks.values) {
      await flush()
    }
  }
}
