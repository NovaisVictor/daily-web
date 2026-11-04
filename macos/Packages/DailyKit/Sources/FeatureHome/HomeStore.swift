import DailyCore
import DailyModels
import Foundation
import Observation

/// What the "Hoje" screen reads: the greeting, the pomodoro and the module summary.
/// It has no endpoint of its own; the pomodoro actions go through the shared
/// `PomodoroController`, which also feeds the menu bar.
@Observable
final class HomeStore {
  @ObservationIgnored private let session: SessionStore
  @ObservationIgnored private let dashboard: DashboardStore
  @ObservationIgnored private let pomodoro: PomodoroController

  init(session: SessionStore, dashboard: DashboardStore, pomodoro: PomodoroController) {
    self.session = session
    self.dashboard = dashboard
    self.pomodoro = pomodoro
  }

  convenience init(environment: AppEnvironment) {
    self.init(session: environment.session, dashboard: environment.dashboard, pomodoro: environment.pomodoro)
  }

  /// `GET /api/me` does not say how many times the person signed in, so the app
  /// cannot tell a first visit (`welcomeKind` in `lib/preferences.ts:220-223`).
  /// Whoever opens the native app has an account already, so it welcomes them back.
  var greeting: Greeting {
    Greeting(user: session.user, welcome: .returning)
  }

  /// Nil until the first state arrives (cache or server).
  func summary(at now: Date) -> HomeSummary? {
    dashboard.state.map { HomeSummary(state: $0, now: now) }
  }

  /// Nil when the server has no timer yet or it is switched off; the web then
  /// renders nothing (`components/Pomodoro.tsx:80`).
  var timer: PomodoroDisplay? {
    guard let display = pomodoro.display, display.enabled else { return nil }
    return display
  }

  var timerError: String? { pomodoro.errorMessage }
  var timerBusy: Bool { pomodoro.isBusy }

  func toggleTimer() async { await pomodoro.toggle() }
  func resetTimer() async { await pomodoro.reset() }
}
