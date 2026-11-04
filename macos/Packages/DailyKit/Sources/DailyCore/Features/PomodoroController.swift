import DailyAPI
import DailyModels
import Foundation
import Observation
import os

/// What the pomodoro widget draws.
public struct PomodoroDisplay: Equatable, Sendable {
  public var enabled: Bool
  public var phase: PomodoroPhase
  public var running: Bool
  /// Counted down locally between polls.
  public var remainingSeconds: Int
  public var completedFocusCount: Int
  public var focusMinutes: Int
  public var restMinutes: Int

  public var isFocus: Bool { phase == .focus }

  /// `MM:SS`, as `formatRemaining` in `components/Pomodoro.tsx:16-24`.
  public var formattedRemaining: String {
    let seconds = max(remainingSeconds, 0)
    return String(format: "%02d:%02d", seconds / 60, seconds % 60)
  }
}

/// The server-side timer with a local one-second tick. The server is only read
/// every 20 s; without the tick the clock would stand still and then jump, so it
/// runs locally and every server value re-anchors it (`components/Pomodoro.tsx:46-63`).
@Observable
public final class PomodoroController {
  public private(set) var display: PomodoroDisplay?
  /// The last failed action, shown under the controls like the web.
  public private(set) var errorMessage: String?
  public private(set) var isBusy = false

  /// Called when the phase changes between two server values.
  @ObservationIgnored public var onPhaseChange: ((PomodoroPhase) -> Void)?

  @ObservationIgnored private let client: any APIClient
  @ObservationIgnored private let dashboard: DashboardStore
  @ObservationIgnored private let now: Now
  @ObservationIgnored private let sleep: Sleeper
  @ObservationIgnored private var server: PomodoroState?
  @ObservationIgnored private var anchor: (seconds: Int, at: Date) = (0, .distantPast)
  @ObservationIgnored private var ticker: Task<Void, Never>?

  public init(
    client: any APIClient,
    dashboard: DashboardStore,
    now: @escaping Now = LiveTime.now,
    sleep: @escaping Sleeper = LiveTime.sleep
  ) {
    self.client = client
    self.dashboard = dashboard
    self.now = now
    self.sleep = sleep
    dashboard.observe { [weak self] change in
      // A cached timer is stale by however long the app was closed.
      guard change.origin != .cache else { return }
      self?.receive(change.current.pomodoro)
    }
  }

  public func start() async { await send(PomodoroEndpoints.start) }
  public func pause() async { await send(PomodoroEndpoints.pause) }
  public func reset() async { await send(PomodoroEndpoints.reset) }

  /// Start when stopped, pause when running: the web's single play/pause button.
  public func toggle() async {
    if display?.running == true { await pause() } else { await start() }
  }

  /// Stops the tick and forgets the timer (sign-out).
  public func clear() {
    ticker?.cancel()
    ticker = nil
    server = nil
    display = nil
    errorMessage = nil
  }

  private func send(_ endpoint: Endpoint<PomodoroState>) async {
    isBusy = true
    defer { isBusy = false }
    do {
      let fresh = try await client.send(endpoint)
      errorMessage = nil
      // Goes through the store, which calls `receive` back.
      dashboard.patch { $0.pomodoro = fresh }
      if dashboard.state == nil { receive(fresh) }
    } catch {
      Logger.core.error("Pomodoro action failed: \(String(describing: error), privacy: .public)")
      errorMessage = error.userMessage
    }
  }

  func receive(_ fresh: PomodoroState) {
    let previous = server
    server = fresh
    if let previous, previous.phase != fresh.phase {
      onPhaseChange?(fresh.phase)
    }
    // Same dependencies as the web's re-anchor effect: an identical answer
    // while paused does not move the clock.
    let changed =
      previous == nil || previous?.remainingSeconds != fresh.remainingSeconds
      || previous?.phase != fresh.phase || previous?.running != fresh.running
    if changed {
      anchor = (fresh.remainingSeconds, now())
    }
    display = PomodoroDisplay(
      enabled: fresh.enabled,
      phase: fresh.phase,
      running: fresh.running,
      remainingSeconds: changed ? fresh.remainingSeconds : (display?.remainingSeconds ?? fresh.remainingSeconds),
      completedFocusCount: fresh.completedFocusCount,
      focusMinutes: fresh.focusMinutes,
      restMinutes: fresh.restMinutes
    )
    updateTicker(running: fresh.running)
  }

  /// One local tick: seconds since the anchor, never below zero.
  func tick() {
    guard var current = display, current.running else { return }
    let elapsed = Int(now().timeIntervalSince(anchor.at).rounded(.down))
    current.remainingSeconds = max(anchor.seconds - elapsed, 0)
    display = current
  }

  private func updateTicker(running: Bool) {
    guard running else {
      ticker?.cancel()
      ticker = nil
      return
    }
    guard ticker == nil else { return }
    let sleep = self.sleep
    ticker = Task { [weak self] in
      while !Task.isCancelled {
        do {
          try await sleep(.seconds(1))
        } catch {
          // Cancelled: the timer stopped or the session ended.
          return
        }
        self?.tick()
      }
    }
  }
}
