import DailyAPI
import DailyCore
import DailyModels
import Foundation
import Testing

@testable import FeatureNotes

/// A note created outside the panel (an e-mail turned note) reaches the notes
/// store through `NotesEvents` (spec 015 FR-015-07, NT-19).
@MainActor
@Suite struct NotesChangedTests {
  let clock = VirtualClock()
  let events = NotesEvents()

  func makeStore(_ client: FakeAPIClient) -> NotesStore {
    let clock = self.clock
    return NotesStore(
      client: client, poller: Poller(sleep: { try await clock.sleep($0) }), shutdown: ShutdownTasks(),
      events: events, sleep: { try await clock.sleep($0) })
  }

  @Test func aNoteCreatedElsewhereReloadsTheListAndOpensIt() async {
    let client = FakeAPIClient(handler: NotesStoreTests.server())
    let store = makeStore(client)
    await store.load()
    #expect(store.activeID == "n1")
    let reads = client.calls.filter { $0.path == "/api/notes" }.count

    events.post(NotesEvents.Change(activate: "n2"))
    await settle()
    #expect(client.calls.filter { $0.path == "/api/notes" }.count == reads + 1)
    #expect(store.activeID == "n2")
    #expect(store.draft == "dois")
  }

  @Test func aChangeWithoutANoteOnlyReloads() async {
    let client = FakeAPIClient(handler: NotesStoreTests.server())
    let store = makeStore(client)
    await store.load(activate: "n3")
    events.post(NotesEvents.Change(activate: nil))
    await settle()
    #expect(client.calls.filter { $0.path == "/api/notes" }.count == 2)
    #expect(store.activeID == "n3")
  }

  /// "Abrir a nota" right after "Criar nota": the notice and the pending note
  /// both ask for the list while it is on its way, and share one read.
  @Test func loadsAskedWhileAReadIsOnItsWayShareIt() async {
    let gate = Gate()
    let client = FakeAPIClient { call throws(APIError) in
      if call.path == "/api/notes" { await gate.wait() }
      return try await NotesStoreTests.server()(call)
    }
    let store = makeStore(client)
    events.post(NotesEvents.Change(activate: nil))
    await settle()
    #expect(gate.waiting == 1)
    let second = Task { await store.load(activate: "n2") }
    await settle()
    // The second load waits for the first read instead of starting its own.
    #expect(gate.waiting == 1)

    gate.releaseOne()
    await second.value
    await settle()
    #expect(client.calls.filter { $0.path == "/api/notes" }.count == 1)
    #expect(store.hasLoaded)
    // The second call's note still opens, over the shared answer.
    #expect(store.activeID == "n2")

    // Once the read ended, the next load reads again.
    let later = Task { await store.load() }
    await settle()
    gate.releaseOne()
    await later.value
    #expect(client.calls.filter { $0.path == "/api/notes" }.count == 2)
  }

  @Test func aSharedReadThatFailsLeavesTheErrorOnce() async {
    let gate = Gate()
    let client = FakeAPIClient { call throws(APIError) in
      if call.path == "/api/notes" {
        await gate.wait()
        throw serverError("falhou", status: 500)
      }
      return try await NotesStoreTests.server()(call)
    }
    let store = makeStore(client)
    let first = Task { await store.load() }
    await settle()
    let second = Task { await store.load() }
    await settle()
    gate.releaseOne()
    await first.value
    await second.value
    #expect(client.calls.filter { $0.path == "/api/notes" }.count == 1)
    #expect(!store.hasLoaded)
    #expect(store.error == "falhou")
  }

  @Test func aReleasedStoreStopsListening() async {
    let client = FakeAPIClient(handler: NotesStoreTests.server())
    var store: NotesStore? = makeStore(client)
    #expect(events.observerCount == 1)
    #expect(store != nil)
    store = nil
    #expect(events.observerCount == 0)
    events.post(NotesEvents.Change(activate: "n2"))
    await settle()
    #expect(client.calls.isEmpty)
  }
}
