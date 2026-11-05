import DailyAPI
import DailyCore
import DailyModels
import DailyStorage
import Foundation
import Testing

@testable import FeatureEmail

/// Spec 015: the remembered view (FR-015-01), the notes notice (FR-015-07)
/// and the drag "maço" (FR-015-04).
@MainActor
@Suite struct EmailRememberedStateTests {
  let client = FakeAPIClient()
  let toasts = quietToasts()
  let navigator = AppNavigator()
  let dashboard: DashboardStore
  let server: FakeServer
  let viewState: ViewStateStore
  let defaults: UserDefaults

  nonisolated static let serverURL = URL(string: "https://daily.example.com") ?? URL(filePath: "/")
  static let inFolder = [
    envelope("7", subject: "Pasta", folder: "Arquivo"),
    envelope("8", subject: "Outra", folder: "Arquivo"),
  ]

  init() {
    let name = "FeatureEmailTests-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: name) else {
      preconditionFailure("Could not create the defaults suite \(name)")
    }
    self.defaults = defaults
    viewState = ViewStateStore(defaults: defaults)
    viewState.activate(server: Self.serverURL, username: "ana")
    let server = FakeServer(EmailStoreTests.state())
    self.server = server
    client.respond { call throws(APIError) in try server.answer(call) }
    let inFolder = Self.inFolder
    server.route { call in
      call.path == "/api/email/messages"
        ? FakeAPIClient.json(EmailMessagesResponse(messages: inFolder, uidvalidity: "1", reindexed: false))
        : nil
    }
    dashboard = DashboardStore(client: client, cache: nil, toasts: toasts)
    dashboard.apply(EmailStoreTests.state())
  }

  /// A store as a new launch builds it: a fresh `ViewStateStore` over the same
  /// disk. The search write does not wait unless `sleep` says otherwise.
  func launch(
    events: NotesEvents? = nil, dashboard: DashboardStore? = nil, viewState: ViewStateStore? = nil,
    sleep: @escaping Sleeper = { _ in }
  ) -> EmailStore {
    EmailStore(
      client: client, dashboard: dashboard ?? self.dashboard, navigator: navigator,
      viewState: viewState ?? ViewStateStore(defaults: defaults), notesEvents: events,
      now: { localDate("2026-10-04T15:00:00") }, sleep: sleep, timeZone: saoPaulo)
  }

  func remembered(_ field: String) -> String? {
    viewState.string(module: EmailStore.viewStateModule, field: field)
  }

  @Test func filtersSurviveARelaunch() async {
    let store = launch()
    store.filters.query = "relatório"
    store.filters.onlyUnread = true
    store.filters.account = "mail-2"
    store.filters.sort = .oldest
    store.filters.groupBy = .sender
    await settle()

    let next = launch()
    #expect(
      next.filters
        == EmailFilters(query: "relatório", onlyUnread: true, account: "mail-2", sort: .oldest, groupBy: .sender))

    next.clearAllFilters()
    await settle()
    let third = launch()
    #expect(third.filters == EmailFilters(sort: .oldest, groupBy: .sender))
  }

  /// A restored full screen would open the panel's sheet over Início at launch
  /// and silence the screen's dialogs: it is not remembered.
  @Test func fullScreenIsNotRemembered() {
    let store = launch()
    store.isFullScreen = true
    #expect(!launch().isFullScreen)
    // A value an earlier version left on disk is ignored too.
    viewState.set(true, module: EmailStore.viewStateModule, field: "maximized")
    #expect(!launch().isFullScreen)
  }

  /// Each field is its own key: a change writes only that one, so it does not
  /// put back what another window changed meanwhile.
  @Test func onlyTheChangedFilterIsWritten() async {
    let store = launch()
    viewState.set(EmailSort.oldest.rawValue, module: EmailStore.viewStateModule, field: EmailStore.Field.sort)
    store.filters.onlyUnread = true
    await settle()
    #expect(viewState.bool(module: EmailStore.viewStateModule, field: EmailStore.Field.onlyUnread) == true)
    #expect(remembered(EmailStore.Field.sort) == EmailSort.oldest.rawValue)
    #expect(remembered(EmailStore.Field.group) == nil)
    #expect(remembered(EmailStore.Field.account) == nil)
    #expect(remembered(EmailStore.Field.query) == nil)
  }

  @Test func theSearchIsWrittenOnceTypingRests() async {
    let sleeper = ManualSleep()
    let store = launch(sleep: { try await sleeper.sleep($0) })
    store.filters.query = "r"
    store.filters.query = "re"
    await settle()
    #expect(sleeper.requested == [EmailStore.queryWriteDelay, EmailStore.queryWriteDelay])
    #expect(remembered(EmailStore.Field.query) == nil)

    sleeper.wakeAll()
    await settle()
    // The first keystroke's write was replaced by the second's.
    #expect(remembered(EmailStore.Field.query) == "re")
    store.filters.onlyUnread = true
    #expect(viewState.bool(module: EmailStore.viewStateModule, field: EmailStore.Field.onlyUnread) == true)
  }

  @Test func folderAndOpenMessageSurviveARelaunch() async {
    let store = launch()
    await store.openFolder(FolderSelection(account: "mail-1", path: "Arquivo"))
    store.open(Self.inFolder[1])

    let next = launch()
    #expect(next.folder == FolderSelection(account: "mail-1", path: "Arquivo"))
    // Until the folder is read the list says it is loading, not that it is empty.
    #expect(next.folderLoading)
    #expect(next.openKey == nil)
    await next.loadRestoredFolder()
    #expect(next.all == Self.inFolder)
    #expect(next.openKey == "mail-1:8")
    // A second view asking again does not read the folder twice.
    let reads = client.actionCalls.filter { $0.path == "/api/email/messages" }.count
    await next.loadRestoredFolder()
    #expect(client.actionCalls.filter { $0.path == "/api/email/messages" }.count == reads)
  }

  @Test func inboxMessageIsReopenedAndAGoneOneIsForgotten() {
    let store = launch()
    store.open(EmailStoreTests.inbox[1])
    let next = launch()
    next.restoreOpenMessage()
    #expect(next.openKey == "mail-1:2")

    viewState.set("mail-1:999", module: EmailStore.viewStateModule, field: EmailStore.Field.open)
    let third = launch()
    third.restoreOpenMessage()
    #expect(third.openKey == nil)
    #expect(viewState.string(module: EmailStore.viewStateModule, field: EmailStore.Field.open) == nil)
  }

  @Test func closingTheMessageAndLeavingTheFolderAreRemembered() async {
    let store = launch()
    await store.openFolder(FolderSelection(account: "mail-1", path: "Arquivo"))
    store.open(Self.inFolder[0])
    store.closeMessage()
    await store.openFolder(FolderSelection(account: "mail-2", path: "INBOX"))
    let next = launch()
    #expect(next.folder == FolderSelection(account: "mail-2", path: "INBOX"))
    #expect(viewState.string(module: EmailStore.viewStateModule, field: EmailStore.Field.open) == nil)
  }

  @Test func anotherAccountDoesNotSeeTheRememberedView() async {
    let store = launch()
    store.filters.query = "segredo"
    await settle()
    let other = ViewStateStore(defaults: defaults)
    other.activate(server: Self.serverURL, username: "bia")
    let theirs = EmailStore(client: client, dashboard: dashboard, navigator: navigator, viewState: other)
    #expect(theirs.filters == EmailFilters())
  }

  /// A store built while the session was still being checked read no
  /// account's view; the sign-in gives it the right one (FR-015-01).
  @Test func aStoreBuiltBeforeTheSignInReadsTheAccountsView() async {
    let store = launch()
    store.filters.query = "relatório"
    await store.openFolder(FolderSelection(account: "mail-1", path: "Arquivo"))
    await settle()

    let signedOut = ViewStateStore(defaults: defaults)
    signedOut.deactivate()
    let early = launch(viewState: signedOut)
    #expect(early.filters == EmailFilters())
    #expect(early.folder == nil)
    let generation = early.restoreGeneration

    signedOut.activate(server: Self.serverURL, username: "ana")
    #expect(early.filters.query == "relatório")
    #expect(early.folder == FolderSelection(account: "mail-1", path: "Arquivo"))
    // The views read the restored folder again when the generation moves.
    #expect(early.restoreGeneration == generation + 1)
    await early.loadRestoredFolder()
    #expect(early.all == Self.inFolder)

    // Signing in again as the same account reads nothing again.
    signedOut.activate(server: Self.serverURL, username: "ana")
    #expect(early.restoreGeneration == generation + 1)
  }

  // MARK: - Remembered message and mailboxes need the server's answer

  @Test func aRememberedMessageWaitsForTheInbox() {
    viewState.set("mail-1:2", module: EmailStore.viewStateModule, field: EmailStore.Field.open)
    let empty = DashboardStore(client: client, cache: nil, toasts: toasts)
    let store = launch(dashboard: empty)
    // No inbox yet: nothing is decided.
    store.restoreOpenMessage()
    #expect(store.openKey == nil)
    #expect(remembered(EmailStore.Field.open) == "mail-1:2")

    // The inbox panel failed: still nothing is decided.
    var failed = EmailStoreTests.state()
    failed.email = PanelResult(data: nil, error: "caixa fora do ar")
    empty.apply(failed)
    store.restoreOpenMessage()
    #expect(store.openKey == nil)
    #expect(remembered(EmailStore.Field.open) == "mail-1:2")

    empty.apply(EmailStoreTests.state())
    store.restoreOpenMessage()
    #expect(store.openKey == "mail-1:2")
  }

  @Test func aCachedInboxWithoutTheMessageDoesNotForgetIt() throws {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "FeatureEmailTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer {
      do {
        try FileManager.default.removeItem(at: directory)
      } catch {
        Issue.record("Could not remove \(directory.path): \(error)")
      }
    }
    let cache = DiskCache<DashboardState>(fileName: "dashboard-state.json", directory: directory)
    try cache.save(EmailStoreTests.state([EmailStoreTests.inbox[0]]))
    let cached = DashboardStore(client: client, cache: cache, toasts: toasts)
    cached.loadCached()
    #expect(cached.state != nil)
    #expect(cached.lastUpdated == nil)

    viewState.set("mail-1:2", module: EmailStore.viewStateModule, field: EmailStore.Field.open)
    let store = launch(dashboard: cached)
    store.restoreOpenMessage()
    #expect(store.openKey == nil)
    #expect(remembered(EmailStore.Field.open) == "mail-1:2")

    // The server's inbox lacks it too: now it is gone.
    cached.apply(EmailStoreTests.state([EmailStoreTests.inbox[0]]))
    store.restoreOpenMessage()
    #expect(store.openKey == nil)
    #expect(remembered(EmailStore.Field.open) == nil)
  }

  @Test func aRememberedAccountOrFolderOfAGoneMailboxIsDropped() {
    let module = EmailStore.viewStateModule
    viewState.set("mail-9", module: module, field: EmailStore.Field.account)
    viewState.set("mail-9", module: module, field: EmailStore.Field.folderAccount)
    viewState.set("Arquivo", module: module, field: EmailStore.Field.folder)

    // Before the server answers, the mailboxes are not known: nothing drops.
    let empty = DashboardStore(client: client, cache: nil, toasts: toasts)
    let store = launch(dashboard: empty)
    store.validateRestoredView()
    #expect(store.filters.account == "mail-9")
    #expect(store.folder == FolderSelection(account: "mail-9", path: "Arquivo"))

    empty.apply(EmailStoreTests.state())
    store.validateRestoredView()
    #expect(store.filters.account == nil)
    #expect(store.folder == nil)
    #expect(!store.folderLoading)
    #expect(remembered(EmailStore.Field.account) == nil)
    #expect(remembered(EmailStore.Field.folderAccount) == nil)
    #expect(remembered(EmailStore.Field.folder) == nil)
  }

  @Test func aRememberedAccountAndFolderStillThereAreKept() {
    let module = EmailStore.viewStateModule
    viewState.set("mail-2", module: module, field: EmailStore.Field.account)
    viewState.set("mail-1", module: module, field: EmailStore.Field.folderAccount)
    viewState.set("Arquivo", module: module, field: EmailStore.Field.folder)
    let store = launch()
    store.validateRestoredView()
    #expect(store.filters.account == "mail-2")
    #expect(store.folder == FolderSelection(account: "mail-1", path: "Arquivo"))
    #expect(remembered(EmailStore.Field.account) == "mail-2")
  }

  // MARK: - Notes notice (FR-015-07)

  @Test func creatingANotePostsNotesChangedWithTheNewNote() async {
    let events = NotesEvents()
    let listener = Listener()
    events.observe(listener) { listener.changes.append($0) }
    server.route { call in
      call.path == "/api/email/to-note" ? FakeAPIClient.json(EmailToNoteResponse(noteId: "n9")) : nil
    }
    let store = launch(events: events)
    await store.create(.note, from: EmailStoreTests.inbox[0], noteFolderId: nil)
    #expect(listener.changes == [NotesEvents.Change(activate: "n9")])

    // "Abrir a nota" only navigates: the notes panel reveals the pending note
    // with its own read, so the notes are not told a second time.
    store.openCreated()
    #expect(listener.changes.count == 1)
    #expect(navigator.route == .module(.notes))
    #expect(navigator.pendingItem(for: .module(.notes)) == "n9")

    // A failure tells nobody.
    server.route { call throws(APIError) in
      if call.path == "/api/email/to-note" {
        throw .server(status: 500, message: "falhou", code: nil, retry: nil)
      }
      return nil
    }
    await store.create(.note, from: EmailStoreTests.inbox[0], noteFolderId: nil)
    #expect(listener.changes.count == 1)
  }

  // MARK: - Drag "maço" (FR-015-04)

  @Test func dragStackGathersTowardTheDraggedRowWithACap() {
    #expect(EmailDragStack.placement(index: 2, dragged: nil) == nil)
    let itself = EmailDragStack.placement(index: 2, dragged: 2)
    #expect(itself == .init(offsetY: 0, scale: 1, zIndex: 10))
    let above = EmailDragStack.placement(index: 1, dragged: 2)
    #expect(above?.offsetY == 10)
    #expect(above?.zIndex == 9)
    let below = EmailDragStack.placement(index: 4, dragged: 2)
    #expect(below?.offsetY == -20)
    // Far rows stop at 28pt and three levels deep.
    let far = EmailDragStack.placement(index: 20, dragged: 2)
    #expect(far?.offsetY == -EmailDragStack.maxOffset)
    #expect(far?.zIndex == 7)
    #expect(far?.scale == EmailDragStack.placement(index: 5, dragged: 2)?.scale)
  }
}

private final class Listener {
  var changes: [NotesEvents.Change] = []
}

/// A `Sleeper` that wakes only when the test says so.
@MainActor
private final class ManualSleep {
  private var sleepers: [CheckedContinuation<Void, any Error>] = []
  private(set) var requested: [Duration] = []

  func sleep(_ duration: Duration) async throws {
    requested.append(duration)
    try await withCheckedThrowingContinuation { sleepers.append($0) }
  }

  /// Wakes every sleeper; a cancelled one finds out on waking.
  func wakeAll() {
    let woken = sleepers
    sleepers = []
    for sleeper in woken { sleeper.resume() }
  }
}
