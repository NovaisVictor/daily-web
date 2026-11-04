import DailyAPI
import DailyModels
import DailyStorage
import Foundation
import Testing

@testable import DailyCore

@Suite struct PomodoroControllerTests {
  let clock = VirtualClock()
  let client = FakeAPIClient()
  let toasts: ToastCenter
  let dashboard: DashboardStore
  let controller: PomodoroController

  init() {
    toasts = quietToasts()
    let clock = self.clock
    dashboard = DashboardStore(client: client, cache: nil, toasts: toasts)
    controller = PomodoroController(
      client: client, dashboard: dashboard, now: { clock.date }, sleep: { try await clock.sleep($0) })
  }

  func timer(_ remaining: Int, phase: PomodoroPhase = .focus, running: Bool = true) -> PomodoroState {
    PomodoroState(
      enabled: true, phase: phase, running: running, remainingSeconds: remaining, focusMinutes: 25,
      restMinutes: 5, completedFocusCount: 0)
  }

  func serve(_ pomodoro: PomodoroState) {
    var state = Fixtures.state()
    state.pomodoro = pomodoro
    dashboard.apply(state)
  }

  @Test func ticksLocallyAndReanchorsOnEveryServerValue() async {
    serve(timer(100))
    #expect(controller.display?.remainingSeconds == 100)
    await clock.advance(by: .seconds(3))
    #expect(controller.display?.remainingSeconds == 97)
    #expect(controller.display?.formattedRemaining == "01:37")

    // The server lags a little behind the local count; its value wins.
    serve(timer(99))
    #expect(controller.display?.remainingSeconds == 99)
    await clock.advance(by: .seconds(1))
    #expect(controller.display?.remainingSeconds == 98)
  }

  @Test func pausedTimerDoesNotTick() async {
    serve(timer(300, running: false))
    await clock.advance(by: .seconds(5))
    #expect(controller.display?.remainingSeconds == 300)
    #expect(clock.pendingSleepers == 0)
  }

  @Test func neverCountsBelowZero() async {
    serve(timer(2))
    await clock.advance(by: .seconds(5))
    #expect(controller.display?.remainingSeconds == 0)
  }

  @Test func phaseChangeIsReportedOncePerChange() {
    var phases: [PomodoroPhase] = []
    controller.onPhaseChange = { phases.append($0) }
    serve(timer(10))
    serve(timer(5))
    serve(timer(300, phase: .rest))
    serve(timer(299, phase: .rest))
    serve(timer(1500, phase: .focus, running: false))
    #expect(phases == [.rest, .focus])
  }

  @Test func actionsPostAndUpdateTheStore() async {
    serve(timer(1500, running: false))
    let started = timer(1500, running: true)
    client.respond { _ in FakeAPIClient.json(started) }
    await controller.toggle()
    #expect(client.calls == [.init(method: "POST", path: "/api/pomodoro/start", body: nil)])
    #expect(dashboard.state?.pomodoro.running == true)
    #expect(controller.display?.running == true)

    let paused = timer(1490, running: false)
    client.respond { _ in FakeAPIClient.json(paused) }
    await controller.toggle()
    await controller.reset()
    #expect(client.calls.map(\.path) == ["/api/pomodoro/start", "/api/pomodoro/pause", "/api/pomodoro/reset"])
  }

  @Test func failedActionShowsTheMessage() async {
    serve(timer(1500, running: false))
    client.respond { _ throws(APIError) in throw .offline }
    await controller.start()
    #expect(controller.errorMessage == "Sem conexão com o servidor.")
    #expect(dashboard.state?.pomodoro.running == false)
  }

  @Test func cachedTimerIsIgnored() throws {
    let directory = Fixtures.temporaryDirectory()
    var cached = Fixtures.state()
    cached.pomodoro = timer(42)
    let cache = DiskCache<DashboardState>(fileName: "state.json", directory: directory)
    try cache.save(cached)
    let store = DashboardStore(client: client, cache: cache, toasts: toasts)
    let other = PomodoroController(client: client, dashboard: store)
    store.loadCached()
    #expect(store.state?.pomodoro.remainingSeconds == 42)
    #expect(other.display == nil)
  }
}
