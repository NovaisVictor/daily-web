import DailyAPI
import DailyCore
import DailyModels
import Foundation
import Testing

@testable import FeatureHome

/// Sleeps forever until cancelled, so the pomodoro tick never fires in a test.
private let parked: Sleeper = { _ in
  try await Task.sleep(for: .seconds(3600))
}

@Suite struct HomeStoreTests {
  let client = FakeAPIClient()
  let storage = InMemorySessionStorage(server: URL(string: "https://daily.example.com"), token: "t")
  let dashboard: DashboardStore
  let session: SessionStore
  let store: HomeStore

  init() {
    let toasts = ToastCenter(sleep: parked)
    dashboard = DashboardStore(client: client, cache: nil, toasts: toasts)
    session = SessionStore(client: client, tokenStore: storage, settings: storage)
    let pomodoro = PomodoroController(client: client, dashboard: dashboard, sleep: parked)
    store = HomeStore(session: session, dashboard: dashboard, pomodoro: pomodoro)
  }

  func timer(enabled: Bool = true, running: Bool, phase: PomodoroPhase = .focus) -> PomodoroState {
    PomodoroState(
      enabled: enabled, phase: phase, running: running, remainingSeconds: 1500, focusMinutes: 25, restMinutes: 5,
      completedFocusCount: 2)
  }

  func serve(_ pomodoro: PomodoroState) {
    var state = Fixtures.full
    state.pomodoro = pomodoro
    dashboard.apply(state)
  }

  @Test func summaryWaitsForTheFirstState() {
    #expect(store.summary(at: Fixtures.now) == nil)
    serve(timer(running: false))
    #expect(store.summary(at: Fixtures.now)?.cards.isEmpty == false)
  }

  @Test func greetsTheSignedInPerson() async {
    #expect(store.greeting.heading == "Olá")
    let user = CurrentUser(username: "ana", isAdmin: false, avatarUrl: nil, fullName: "Ana Souza", email: nil)
    client.respond { _ in FakeAPIClient.json(user) }
    await session.restore()
    #expect(store.greeting.heading == "Olá, Ana")
    #expect(store.greeting.welcome == "Bem-vindo de volta")
  }

  @Test func timerIsHiddenWhenDisabled() {
    #expect(store.timer == nil)
    serve(timer(enabled: false, running: false))
    #expect(store.timer == nil)
    serve(timer(running: false))
    #expect(store.timer?.completedFocusCount == 2)
    #expect(store.timer?.formattedRemaining == "25:00")
  }

  @Test func toggleStartsAStoppedTimer() async {
    serve(timer(running: false))
    let answer = FakeAPIClient.json(timer(running: true))
    client.respond { _ in answer }
    await store.toggleTimer()
    #expect(client.calls == [FakeAPIClient.Call(method: "POST", path: "/api/pomodoro/start", body: nil)])
    #expect(store.timer?.running == true)
    #expect(store.timerError == nil)
  }

  @Test func togglePausesARunningTimer() async {
    serve(timer(running: true))
    let answer = FakeAPIClient.json(timer(running: false))
    client.respond { _ in answer }
    await store.toggleTimer()
    #expect(client.calls == [FakeAPIClient.Call(method: "POST", path: "/api/pomodoro/pause", body: nil)])
    #expect(store.timer?.running == false)
  }

  @Test func resetPostsReset() async {
    serve(timer(running: true))
    let answer = FakeAPIClient.json(timer(running: false))
    client.respond { _ in answer }
    await store.resetTimer()
    #expect(client.calls == [FakeAPIClient.Call(method: "POST", path: "/api/pomodoro/reset", body: nil)])
  }

  @Test func serverErrorIsShownAndTheTimerStays() async {
    serve(timer(running: false))
    client.respond { _ throws(APIError) in
      throw .server(status: 500, message: "Falha ao atualizar pomodoro", code: nil, retry: nil)
    }
    await store.toggleTimer()
    #expect(store.timerError == "Falha ao atualizar pomodoro")
    #expect(store.timer?.running == false)
    #expect(!store.timerBusy)
  }
}
