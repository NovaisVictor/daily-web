import DailyAPI
import DailyCore
import DailyModels
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

  /// A store as a new launch builds it: a fresh `ViewStateStore` over the same disk.
  func launch(events: NotesEvents? = nil) -> EmailStore {
    let relaunched = ViewStateStore(defaults: defaults)
    return EmailStore(
      client: client, dashboard: dashboard, toasts: toasts, navigator: navigator,
      viewState: relaunched, notesEvents: events,
      now: { localDate("2026-10-04T15:00:00") }, timeZone: saoPaulo)
  }

  @Test func filtersAndFullScreenSurviveARelaunch() {
    let store = launch()
    store.filters.query = "relatório"
    store.filters.onlyUnread = true
    store.filters.account = "mail-2"
    store.filters.sort = .oldest
    store.filters.groupBy = .sender
    store.isFullScreen = true

    let next = launch()
    #expect(
      next.filters
        == EmailFilters(query: "relatório", onlyUnread: true, account: "mail-2", sort: .oldest, groupBy: .sender))
    #expect(next.isFullScreen)

    next.clearAllFilters()
    next.isFullScreen = false
    let third = launch()
    #expect(third.filters == EmailFilters(sort: .oldest, groupBy: .sender))
    #expect(!third.isFullScreen)
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

  @Test func anotherAccountDoesNotSeeTheRememberedView() {
    let store = launch()
    store.filters.query = "segredo"
    let other = ViewStateStore(defaults: defaults)
    other.activate(server: Self.serverURL, username: "bia")
    let theirs = EmailStore(
      client: client, dashboard: dashboard, toasts: toasts, navigator: navigator, viewState: other)
    #expect(theirs.filters == EmailFilters())
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
