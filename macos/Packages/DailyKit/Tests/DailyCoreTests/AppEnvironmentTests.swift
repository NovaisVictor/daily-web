import DailyAPI
import DailyModels
import DailyStorage
import Foundation
import Testing

@testable import DailyCore

@Suite struct AppEnvironmentTests {
  @Test func previewIsSignedInWithSampleData() {
    let environment = AppEnvironment.preview()
    #expect(environment.session.user == PreviewFixtures.user)
    #expect(environment.dashboard.state == PreviewFixtures.dashboard)
  }

  @Test func previewClientAnswersWithoutNetwork() async throws {
    let client = PreviewAPIClient(state: PreviewFixtures.dashboard, user: PreviewFixtures.user)
    #expect(try await client.send(CoreEndpoints.me) == PreviewFixtures.user)
    #expect(try await client.send(PomodoroEndpoints.start) == PreviewFixtures.dashboard.pomodoro)
  }

  @Test func unauthorizedFromAFeatureCallSignsOutAndClears() async throws {
    let fake = FakeAPIClient()
    let storage = InMemorySessionStorage(server: URL(string: "https://daily.example.com"), token: "t")
    let clock = VirtualClock()
    let environment = AppEnvironment(
      rawClient: fake,
      tokenStore: storage,
      settings: storage,
      cacheDirectory: Fixtures.temporaryDirectory(),
      defaults: Fixtures.defaults(),
      poster: FakeNotificationPoster(),
      now: { clock.date },
      sleep: { try await clock.sleep($0) }
    )
    fake.respond { call in
      call.path == "/api/me" ? FakeAPIClient.json(Fixtures.user) : FakeAPIClient.json(Fixtures.state())
    }
    await environment.launch()
    await settle()
    #expect(environment.session.user == Fixtures.user)
    #expect(environment.dashboard.state == Fixtures.state())
    #expect(environment.poller.isRunning)

    fake.respond { _ throws(APIError) in throw .unauthorized }
    await #expect(throws: APIError.unauthorized) {
      try await environment.client.send(PomodoroEndpoints.start)
    }
    #expect(environment.session.phase == .signedOut(message: SessionStore.expiredMessage))
    #expect(environment.dashboard.state == nil)
    #expect(!environment.poller.isRunning)
  }

  /// A notification action that launched the app runs before `launch()` ends.
  @Test func waitUntilSignedInWaitsForTheSessionAndAState() async {
    let fake = FakeAPIClient()
    let storage = InMemorySessionStorage(server: URL(string: "https://daily.example.com"), token: "t")
    let environment = AppEnvironment(
      rawClient: fake, tokenStore: storage, settings: storage, cacheDirectory: nil,
      defaults: Fixtures.defaults(), poster: FakeNotificationPoster(),
      sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
    fake.respond { call in
      call.path == "/api/me" ? FakeAPIClient.json(Fixtures.user) : FakeAPIClient.json(Fixtures.state())
    }
    let ready = Task { await environment.waitUntilSignedIn() }
    await environment.launch()
    #expect(await ready.value)
    #expect(environment.dashboard.state == Fixtures.state())
    environment.poller.stop()
  }

  @Test func waitUntilSignedInIsFalseWhenSignedOut() async {
    let storage = InMemorySessionStorage(server: URL(string: "https://daily.example.com"), token: nil)
    let environment = AppEnvironment(
      rawClient: FakeAPIClient(), tokenStore: storage, settings: storage, cacheDirectory: nil,
      defaults: Fixtures.defaults(), poster: FakeNotificationPoster())
    await environment.launch()
    #expect(await environment.waitUntilSignedIn() == false)
  }

  @Test func launchWithAnExpiredSessionClearsThePreviousAccount() async throws {
    let fake = FakeAPIClient()
    let storage = InMemorySessionStorage(server: URL(string: "https://daily.example.com"), token: "t")
    let directory = Fixtures.temporaryDirectory()
    let cache = DiskCache<DashboardState>(fileName: "dashboard-state.json", directory: directory)
    try cache.save(Fixtures.state())
    let environment = AppEnvironment(
      rawClient: fake,
      tokenStore: storage,
      settings: storage,
      cacheDirectory: directory,
      defaults: Fixtures.defaults(),
      poster: FakeNotificationPoster()
    )
    fake.respond { _ throws(APIError) in throw .unauthorized }
    await environment.launch()
    #expect(environment.session.phase == .signedOut(message: SessionStore.expiredMessage))
    #expect(try cache.load() == nil)
  }

  @Test func signInLoadsThatAccountsAppearance() async throws {
    let fake = FakeAPIClient()
    let storage = InMemorySessionStorage(server: URL(string: "https://daily.example.com"), token: "t")
    let defaults = Fixtures.defaults()
    let environment = AppEnvironment(
      rawClient: fake,
      tokenStore: storage,
      settings: storage,
      cacheDirectory: nil,
      defaults: defaults,
      poster: FakeNotificationPoster()
    )
    fake.respond { call in
      switch call.path {
      case "/api/me": FakeAPIClient.json(Fixtures.user)
      case "/api/preferences": FakeAPIClient.json(AppearanceResponse(appearance: Appearance(theme: .dark)))
      default: FakeAPIClient.json(Fixtures.state())
      }
    }
    await environment.launch()
    await environment.preferences.updateAppearance(Appearance(theme: .dark))
    await environment.session.signOut()
    #expect(environment.preferences.appearance == Appearance())

    let server = try #require(storage.serverURL)
    #expect(await environment.session.signIn(server: server, username: "ana", password: "x") == nil)
    #expect(environment.preferences.appearance == Appearance(theme: .dark))
    environment.poller.stop()
  }
}
