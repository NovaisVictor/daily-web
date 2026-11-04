import DailyAPI
import DailyModels
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
}
