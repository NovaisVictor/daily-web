import DailyAPI
import DailyModels
import DailyStorage
import Foundation
import Observation
import os

/// Every core store, wired together. The app builds one at launch and hands
/// the stores and `client` to the features.
@Observable
public final class AppEnvironment {
  public let session: SessionStore
  /// The client features receive: a 401 from any call signs the app out.
  public let client: any APIClient
  public let dashboard: DashboardStore
  public let poller: Poller
  public let preferences: PreferencesStore
  public let pomodoro: PomodoroController
  public let focus: FocusScheduler
  public let alerts: AlertEngine
  public let toasts: ToastCenter
  public let navigator = AppNavigator()
  public let shutdown = ShutdownTasks()

  /// The app's graph: `HTTPAPIClient`, Keychain token, caches under
  /// Application Support and `UNUserNotificationCenter`.
  public convenience init(
    settings: any ServerSettings,
    tokenStore: any SessionTokenStore,
    urlSession: URLSession = URLSession(configuration: HTTPAPIClient.makeSessionConfiguration()),
    defaults: UserDefaults = .standard
  ) {
    let client = HTTPAPIClient(tokenStore: tokenStore, settings: settings, session: urlSession)
    self.init(
      rawClient: client,
      tokenStore: tokenStore,
      settings: settings,
      cacheDirectory: Self.defaultCacheDirectory,
      defaults: defaults,
      poster: UserNotificationPoster()
    )
  }

  /// Wires the graph around any client; tests and previews use this one.
  ///
  /// - Parameter cacheDirectory: nil keeps nothing on disk.
  public init(
    rawClient: any APIClient,
    tokenStore: any SessionTokenStore,
    settings: any ServerSettings,
    cacheDirectory: URL?,
    defaults: UserDefaults,
    poster: any NotificationPosting,
    now: @escaping Now = LiveTime.now,
    sleep: @escaping Sleeper = LiveTime.sleep
  ) {
    let toasts = ToastCenter(sleep: sleep)
    let session = SessionStore(client: rawClient, tokenStore: tokenStore, settings: settings)
    let client = SessionAwareClient(rawClient) { [weak session] in session?.invalidate() }
    let dashboard = DashboardStore(
      client: client,
      cache: cacheDirectory.map { DiskCache(fileName: "dashboard-state.json", directory: $0) },
      toasts: toasts,
      now: now
    )
    let poller = Poller(sleep: sleep)
    let alerts = AlertEngine(
      poster: poster,
      cache: cacheDirectory.map { DiskCache(fileName: "desktop-alerts.json", directory: $0) },
      defaults: defaults,
      now: now
    )
    let pomodoro = PomodoroController(client: client, dashboard: dashboard, now: now, sleep: sleep)
    let preferences = PreferencesStore(client: client, dashboard: dashboard, toasts: toasts, defaults: defaults)
    let focus = FocusScheduler(client: client, dashboard: dashboard, toasts: toasts, now: now)

    dashboard.observe { change in
      guard change.origin == .server else { return }
      Task { await alerts.process(change.current) }
    }
    pomodoro.onPhaseChange = { phase in
      Task { await alerts.pomodoroPhaseChanged(phase) }
    }
    poller.register(
      Poller.ScopeID.state,
      foreground: Poller.Cadence.stateForeground,
      background: Poller.Cadence.stateBackground
    ) { await dashboard.reload() }
    poller.register(
      Poller.ScopeID.reminders,
      foreground: Poller.Cadence.reminders,
      background: Poller.Cadence.reminders
    ) { await alerts.checkReminders() }

    session.onSignedIn = { user in
      if let server = settings.serverURL {
        preferences.activate(server: server, username: user.username)
      } else {
        Logger.core.error("Signed in without a server URL; the appearance stays in memory")
        preferences.deactivate()
      }
      dashboard.loadCached()
      poller.start()
    }
    session.onSignedOut = {
      poller.stop()
      dashboard.clear()
      pomodoro.clear()
      alerts.reset()
      preferences.deactivate()
    }

    self.session = session
    self.client = client
    self.dashboard = dashboard
    self.poller = poller
    self.preferences = preferences
    self.pomodoro = pomodoro
    self.focus = focus
    self.alerts = alerts
    self.toasts = toasts
  }

  /// Checks the stored session; on success the dashboard starts polling.
  public func launch() async {
    await session.restore()
  }

  /// From `scenePhase` / window occlusion: hidden counts as background.
  public func setForeground(_ foreground: Bool) {
    poller.setForeground(foreground)
  }

  /// `Application Support/<bundle id>/`.
  public static var defaultCacheDirectory: URL {
    URL.applicationSupportDirectory.appending(
      path: Bundle.main.bundleIdentifier ?? "io.github.novaisvictor.dailyweb", directoryHint: .isDirectory)
  }

  /// Signed in with sample data and a fake client; nothing touches the network or disk.
  public static func preview(
    state: DashboardState = PreviewFixtures.dashboard,
    user: CurrentUser = PreviewFixtures.user
  ) -> AppEnvironment {
    let server = URL(string: "https://daily.example.com")
    let storage = InMemorySessionStorage(server: server, token: "preview")
    // A suite of its own keeps previews from writing the app's preferences;
    // `.standard` is only the fallback for an unusable suite name.
    let defaults = UserDefaults(suiteName: "io.github.novaisvictor.dailyweb.preview") ?? .standard
    let environment = AppEnvironment(
      rawClient: PreviewAPIClient(state: state, user: user),
      tokenStore: storage,
      settings: storage,
      cacheDirectory: nil,
      defaults: defaults,
      poster: SilentNotificationPoster()
    )
    environment.session.assumeSignedIn(user)
    environment.dashboard.apply(state)
    return environment
  }
}
