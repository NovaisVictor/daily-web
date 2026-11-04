import DailyStorage
import Foundation
import Synchronization
import os

/// Saves a `DiskCache` off the main actor. Only the latest value waiting to be
/// written matters, so a burst of changes costs one write, not one per change.
nonisolated final class CacheWriter<Value: Codable & Sendable>: Sendable {
  private struct State {
    var pending: Value?
    var drain: Task<Void, Never>?
    /// Bumped by `remove()`; a write taken before it must not land after it.
    var epoch = 0
  }

  private let cache: DiskCache<Value>
  private let label: String
  private let state = Mutex(State())
  /// Serializes disk access between the background writes and `remove()`.
  private let disk = Mutex(())

  init(cache: DiskCache<Value>, label: String) {
    self.cache = cache
    self.label = label
  }

  /// Queues `value`, replacing any value not written yet.
  func save(_ value: Value) {
    state.withLock { state in
      state.pending = value
      guard state.drain == nil else { return }
      state.drain = Task.detached(priority: .utility) { [self] in drain() }
    }
  }

  /// Deletes the file now and drops every pending write. Waits for a write
  /// already on disk to finish, so the file cannot come back afterwards.
  func remove() throws {
    try disk.withLock { _ in
      state.withLock { state in
        state.pending = nil
        state.epoch += 1
      }
      try cache.remove()
    }
  }

  /// Waits until every queued value is on disk.
  func flush() async {
    while let drain = state.withLock({ $0.drain }) {
      await drain.value
    }
  }

  private func drain() {
    while true {
      let next: (value: Value, epoch: Int)? = state.withLock { state in
        guard let value = state.pending else {
          state.drain = nil
          return nil
        }
        state.pending = nil
        return (value, state.epoch)
      }
      guard let next else { return }
      disk.withLock { _ in
        guard state.withLock({ $0.epoch }) == next.epoch else { return }
        do {
          try cache.save(next.value)
        } catch {
          // The cache only speeds up the next launch; the app works without it.
          Logger.core.error(
            "Could not save the \(self.label, privacy: .public) cache: \(String(describing: error), privacy: .public)")
        }
      }
    }
  }
}
