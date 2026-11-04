import Foundation
import os

/// Waits for the given duration. Stores take it as a dependency so tests drive
/// time with a virtual clock instead of waiting.
public typealias Sleeper = @MainActor (Duration) async throws -> Void

/// The wall clock. Injected for the same reason as `Sleeper`.
public typealias Now = @MainActor () -> Date

/// Real-time defaults for `Sleeper` and `Now`.
public nonisolated enum LiveTime {
  public static func sleep(_ duration: Duration) async throws {
    try await Task.sleep(for: duration)
  }

  public static func now() -> Date { Date() }
}

nonisolated extension Logger {
  static let core = Logger(subsystem: "io.github.novaisvictor.dailyweb", category: "DailyCore")
}
