import DailyModels
import DailyStorage
import Foundation
import Observation
import os

/// System notifications with the web's rules (`lib/hooks/useDesktopAlerts.tsx`).
///
/// Every new dashboard state is compared with what was already announced; the
/// announced keys live on disk, so a relaunch does not repeat them. A source
/// seen for the first time (first launch, or the first load after sign-in,
/// since sign-out forgets the keys) only records its baseline.
@Observable
public final class AlertEngine {
  /// `ENABLED_KEY`, `lib/desktopAlertsStorage.ts:4`, with the same `"1"`/`"0"` values.
  public static let enabledKey = "daily-web.desktop-alerts.enabled"

  public private(set) var isEnabled: Bool

  @ObservationIgnored private let poster: any NotificationPosting
  @ObservationIgnored private let cache: DiskCache<SeenState>?
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let now: Now
  @ObservationIgnored private let calendar: Calendar
  @ObservationIgnored private var seen: SeenState
  @ObservationIgnored private var agenda: [AgendaItem] = []
  @ObservationIgnored private var lastUpdatedAt: String?

  /// - Parameters:
  ///   - cache: Where the announced keys live (`SEEN_KEY` in the web).
  ///   - calendar: Reads agenda dates and times as local time.
  public init(
    poster: any NotificationPosting,
    cache: DiskCache<SeenState>?,
    defaults: UserDefaults,
    now: @escaping Now = LiveTime.now,
    calendar: Calendar = .current
  ) {
    self.poster = poster
    self.cache = cache
    self.defaults = defaults
    self.now = now
    self.calendar = calendar
    isEnabled = defaults.string(forKey: Self.enabledKey) == "1"
    seen = Self.loadSeen(cache)
  }

  /// Asks for permission and turns alerts on when granted (`enable`, `useDesktopAlerts.tsx:64-71`).
  public func enable() async {
    guard await poster.requestAuthorization() else { return }
    setEnabled(true)
  }

  public func disable() {
    setEnabled(false)
  }

  /// A full state from the server. Runs once per `updatedAt`, like the web's
  /// effect (`useDesktopAlerts.tsx:52-58`).
  public func process(_ state: DashboardState) async {
    agenda = state.agenda.data ?? []
    guard state.updatedAt != lastUpdatedAt else { return }
    lastUpdatedAt = state.updatedAt
    let result = AlertRules.diff(seen, AlertRules.currentAlerts(state))
    store(result.seen)
    await show(result.alerts)
    await checkReminders()
  }

  /// Agenda reminders, every 30 s (`useDesktopAlerts.tsx:44-50`, `:60-63`).
  public func checkReminders() async {
    let result = AlertRules.dueReminders(agenda, now: now(), seen: seen, calendar: calendar)
    store(result.seen)
    await show(result.alerts)
  }

  /// The agent tasks waiting on the user right now; only new ones alert.
  public func updateAgents(_ waiting: [AgentAttention]) async {
    let alerts = AlertRules.agentAlerts(waiting)
    let result = AlertRules.diff(seen, [.agent: alerts])
    store(result.seen)
    await show(result.alerts)
  }

  /// The pomodoro moved to `phase` (`notifyPhaseChange`, `components/Pomodoro.tsx:29-39`).
  /// Like the web, it does not depend on the dashboard alerts switch, only on
  /// the system permission.
  public func pomodoroPhaseChanged(_ phase: PomodoroPhase) async {
    guard await poster.isAuthorized() else { return }
    let message = phase == .focus ? "Hora de focar" : "Hora de descansar"
    await poster.post(
      DesktopAlert(tag: "pomodoro", title: "daily-web", body: message, target: AlertTarget(route: .today)))
  }

  /// Forgets what was announced (sign-out), so the next account's first load
  /// is a baseline instead of a flood.
  public func reset() {
    seen = SeenState()
    agenda = []
    lastUpdatedAt = nil
    guard let cache else { return }
    do {
      try cache.remove()
    } catch {
      Logger.core.error("Could not delete the alert keys: \(String(describing: error), privacy: .public)")
    }
  }

  private func show(_ alerts: [DesktopAlert]) async {
    guard isEnabled, !alerts.isEmpty, await poster.isAuthorized() else { return }
    for alert in AlertRules.summarize(alerts) {
      await poster.post(alert)
    }
  }

  private func setEnabled(_ enabled: Bool) {
    defaults.set(enabled ? "1" : "0", forKey: Self.enabledKey)
    isEnabled = enabled
  }

  private func store(_ next: SeenState) {
    guard next != seen else { return }
    seen = next
    guard let cache else { return }
    do {
      try cache.save(next)
    } catch {
      // Same fallback as `saveSeen` (`desktopAlertsStorage.ts:41-47`): memory
      // keeps working; a relaunch takes a new baseline.
      Logger.core.error("Could not save the alert keys: \(String(describing: error), privacy: .public)")
    }
  }

  private static func loadSeen(_ cache: DiskCache<SeenState>?) -> SeenState {
    guard let cache else { return SeenState() }
    do {
      return try cache.load() ?? SeenState()
    } catch {
      // `loadSeen` (`desktopAlertsStorage.ts:29-38`) starts over on bad data.
      Logger.core.error(
        "Alert keys unreadable; starting a new baseline: \(String(describing: error), privacy: .public)")
      return SeenState()
    }
  }
}
