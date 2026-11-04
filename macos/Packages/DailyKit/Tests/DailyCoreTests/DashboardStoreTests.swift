import DailyAPI
import DailyModels
import DailyStorage
import Foundation
import Testing

@testable import DailyCore

@Suite struct DashboardStoreTests {
  let client = FakeAPIClient()
  let toasts: ToastCenter
  let directory = Fixtures.temporaryDirectory()

  init() {
    toasts = quietToasts()
  }

  var cache: DiskCache<DashboardState> { DiskCache(fileName: "state.json", directory: directory) }

  func makeStore() -> DashboardStore {
    DashboardStore(client: client, cache: cache, toasts: toasts, now: { VirtualClock.origin })
  }

  @Test func showsTheCacheBeforeTheServerAnswers() async throws {
    let cached = Fixtures.state(updatedAt: "cached")
    try cache.save(cached)
    let gate = Gate()
    let fresh = Fixtures.state(updatedAt: "fresh")
    client.respond { _ in
      await gate.wait()
      return FakeAPIClient.json(fresh)
    }
    let store = makeStore()
    let loading = Task { await store.start() }
    await settle()
    #expect(store.state == cached)
    #expect(store.lastUpdated == nil)

    gate.open()
    await loading.value
    #expect(store.state == fresh)
    #expect(store.lastUpdated == VirtualClock.origin)
    await store.flushCache()
    #expect(try cache.load() == fresh)
    #expect(client.calls == [.init(method: "GET", path: "/api/state", body: nil)])
  }

  @Test func failedReloadKeepsTheStateAndRecordsTheError() async {
    let store = makeStore()
    store.apply(Fixtures.state())
    client.respond { _ throws(APIError) in throw .offline }
    await store.reload()
    #expect(store.state == Fixtures.state())
    #expect(store.lastError == .offline)
    #expect(toasts.toasts.isEmpty)
  }

  @Test func manualRefreshPostsAndToastsFailures() async {
    let store = makeStore()
    client.respond { _ in FakeAPIClient.json(Fixtures.state(updatedAt: "refreshed")) }
    await store.refresh()
    #expect(client.calls.last == .init(method: "POST", path: "/api/refresh", body: nil))
    #expect(store.state?.updatedAt == "refreshed")
    #expect(!store.isRefreshing)

    client.respond { _ throws(APIError) in throw .timedOut }
    await store.refresh()
    #expect(toasts.toasts.map(\.text) == ["O servidor demorou para responder."])
    #expect(toasts.toasts.first?.kind == .error)
  }

  @Test func mutateAppliesAtOnceAndKeepsOnSuccess() async {
    let store = makeStore()
    store.apply(Fixtures.state())
    var seenDuringCommit: TasksView?
    let error = await store.mutate {
      $0.tasksView = .board
    } commit: { () async throws(APIError) in
      seenDuringCommit = store.state?.tasksView
    }
    #expect(error == nil)
    #expect(seenDuringCommit == .board)
    #expect(store.state?.tasksView == .board)
    #expect(toasts.toasts.isEmpty)
  }

  @Test func mutateRollsBackAndToastsOnFailure() async throws {
    let store = makeStore()
    store.apply(Fixtures.state())
    let failure = APIError.server(status: 500, message: "falhou", code: nil, retry: nil)
    let error = await store.mutate {
      $0.tasksView = .board
    } commit: { () async throws(APIError) in
      throw failure
    }
    #expect(error == failure)
    #expect(store.state == Fixtures.state())
    await store.flushCache()
    #expect(try cache.load() == Fixtures.state())
    #expect(toasts.toasts.map(\.text) == ["falhou"])
  }

  @Test func readInFlightDoesNotOverwriteAMutation() async {
    let store = makeStore()
    store.apply(Fixtures.state())
    let gate = Gate()
    client.respond { _ in
      await gate.wait()
      // Carries the state from before the change.
      return FakeAPIClient.json(Fixtures.state(updatedAt: "stale"))
    }
    let polling = Task { await store.reload() }
    await settle()
    await store.mutate {
      $0.tasksView = .board
    } commit: { () async throws(APIError) in
    }
    gate.open()
    await polling.value
    #expect(store.state?.tasksView == .board)
    #expect(store.state?.updatedAt != "stale")
  }

  @Test func readStartedDuringTheCommitIsDiscarded() async {
    let store = makeStore()
    store.apply(Fixtures.state())
    client.respond { _ in FakeAPIClient.json(Fixtures.state(updatedAt: "stale")) }
    await store.mutate {
      $0.tasksView = .board
    } commit: { () async throws(APIError) in
      await store.reload()
    }
    #expect(store.state?.tasksView == .board)
  }

  @Test func applyAndPatchNotifyListeners() {
    let store = makeStore()
    var origins: [DashboardChange.Origin] = []
    store.observe { origins.append($0.origin) }
    store.apply(Fixtures.state())
    store.patch { $0.agendaDays = 7 }
    #expect(origins == [.server, .local])
    #expect(store.state?.agendaDays == 7)
  }

  @Test func clearForgetsMemoryAndCache() async throws {
    let store = makeStore()
    store.apply(Fixtures.state())
    await store.flushCache()
    #expect(try cache.load() != nil)
    store.clear()
    #expect(store.state == nil)
    #expect(store.lastUpdated == nil)
    #expect(try cache.load() == nil)
  }

  @Test func clearDropsAWriteStillQueued() async throws {
    let store = makeStore()
    store.apply(Fixtures.state())
    store.clear()
    await store.flushCache()
    #expect(try cache.load() == nil)
  }

  @Test func unchangedStateIsNotWrittenAgain() async throws {
    let store = makeStore()
    var changes = 0
    store.observe { _ in changes += 1 }
    store.apply(Fixtures.state())
    await store.flushCache()
    try cache.remove()

    store.apply(Fixtures.state())
    await store.flushCache()
    #expect(try cache.load() == nil)
    #expect(changes == 2)

    store.apply(Fixtures.state(updatedAt: "changed"))
    await store.flushCache()
    #expect(try cache.load() == Fixtures.state(updatedAt: "changed"))
  }

  @Test func failedReadAfterClearDoesNotRecordTheError() async {
    let store = makeStore()
    store.apply(Fixtures.state())
    let gate = Gate()
    client.respond { _ throws(APIError) in
      await gate.wait()
      throw .unauthorized
    }
    let polling = Task { await store.reload() }
    await settle()
    // The sign-out the 401 causes runs before the read reports back.
    store.clear()
    gate.open()
    await polling.value
    #expect(store.lastError == nil)
    #expect(store.state == nil)
  }

  @Test func failedRefreshAfterClearShowsNoToast() async {
    let store = makeStore()
    let gate = Gate()
    client.respond { _ throws(APIError) in
      await gate.wait()
      throw .unauthorized
    }
    let refreshing = Task { await store.refresh() }
    await settle()
    store.clear()
    gate.open()
    await refreshing.value
    #expect(toasts.toasts.isEmpty)
  }
}
