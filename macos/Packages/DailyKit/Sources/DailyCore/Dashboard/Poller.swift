import Foundation
import Observation

/// Runs registered actions on a cadence that depends on whether a window is
/// visible (docs/plan.md, "Polling, ciclo de vida e avisos").
///
/// A scope never overlaps itself: a tick that comes while the previous run is
/// still going is skipped. Runs are not cancelled when the cadence changes or a
/// scope goes away; the stores discard answers they no longer want.
@Observable
public final class Poller {
  /// Scope ids the app registers.
  public enum ScopeID {
    public static let state = "state"
    public static let agents = "agents"
    /// The minute check for agent tasks waiting on the user, off while `agents` runs.
    public static let agentAttention = "agentAttention"
    public static let notesSync = "notesSync"
    public static let reminders = "alertReminders"
  }

  /// Cadences from the plan and the web (`usePolling.tsx:6`, `useAgentPolling.ts:35`).
  public enum Cadence {
    public static let stateForeground = Duration.seconds(20)
    public static let stateBackground = Duration.seconds(60)
    public static let agents = Duration.seconds(2)
    /// Alerts only; the screen, when shown, reads every 2 s.
    public static let agentAttention = Duration.seconds(60)
    public static let notesSync = Duration.seconds(10)
    /// `useDesktopAlerts.tsx:61`.
    public static let reminders = Duration.seconds(30)
  }

  private struct Scope {
    let foreground: Duration
    /// nil pauses the scope while no window is visible.
    let background: Duration?
    let action: @MainActor () async -> Void
  }

  public private(set) var isForeground = true
  /// Between `start()` and `stop()`.
  public private(set) var isRunning = false

  @ObservationIgnored private let sleep: Sleeper
  @ObservationIgnored private var scopes: [String: Scope] = [:]
  @ObservationIgnored private var loops: [String: Task<Void, Never>] = [:]
  @ObservationIgnored private var inFlight: Set<String> = []

  public init(sleep: @escaping Sleeper = LiveTime.sleep) {
    self.sleep = sleep
  }

  public var registeredScopes: Set<String> { Set(scopes.keys) }

  /// Adds or replaces a scope. While the poller runs, the action runs at once
  /// and then every `foreground` (or `background`) interval.
  public func register(
    _ id: String,
    foreground: Duration,
    background: Duration?,
    action: @escaping @MainActor () async -> Void
  ) {
    scopes[id] = Scope(foreground: foreground, background: background, action: action)
    restart(id, runFirst: true)
  }

  public func unregister(_ id: String) {
    scopes[id] = nil
    loops.removeValue(forKey: id)?.cancel()
  }

  /// Starts every registered scope, each running once right away.
  public func start() {
    guard !isRunning else { return }
    isRunning = true
    for id in scopes.keys { restart(id, runFirst: true) }
  }

  /// Stops every loop (sign-out). Registrations stay for the next `start()`.
  public func stop() {
    isRunning = false
    for loop in loops.values { loop.cancel() }
    loops.removeAll()
  }

  /// Switches every scope to the new cadence now. Coming back to the
  /// foreground runs each scope at once, as the agents board does on
  /// `visibilitychange` (`useAgentPolling.ts:31-34`).
  public func setForeground(_ foreground: Bool) {
    guard foreground != isForeground else { return }
    isForeground = foreground
    for id in scopes.keys { restart(id, runFirst: foreground) }
  }

  /// Runs a scope now, unless it is already running.
  public func runNow(_ id: String) async {
    await runOnce(id)
  }

  private func restart(_ id: String, runFirst: Bool) {
    loops.removeValue(forKey: id)?.cancel()
    guard isRunning, scopes[id] != nil else { return }
    loops[id] = Task { [weak self] in
      await self?.loop(id, runFirst: runFirst)
    }
  }

  private func loop(_ id: String, runFirst: Bool) async {
    var shouldRun = runFirst
    while !Task.isCancelled {
      if shouldRun { await runOnce(id) }
      shouldRun = true
      guard !Task.isCancelled, let scope = scopes[id] else { return }
      guard let interval = isForeground ? scope.foreground : scope.background else {
        // Paused in the background; `setForeground(true)` starts a new loop.
        return
      }
      do {
        try await sleep(interval)
      } catch {
        // The only error a sleeper throws is cancellation: this loop was replaced or stopped.
        return
      }
    }
  }

  private func runOnce(_ id: String) async {
    guard let scope = scopes[id], !inFlight.contains(id) else { return }
    inFlight.insert(id)
    // A separate task, so cancelling the loop (cadence change) does not cancel
    // the request already on the wire.
    let run = Task { await scope.action() }
    await run.value
    inFlight.remove(id)
  }
}
